require 'base64'

module ActiveMerchant
  module Billing
    class RedunicreGateway < Gateway

      TEST_URLS = {
        :web    => 'https://homologation.payline.com/V4/services/WebPaymentAPI',
        :direct => 'https://homologation.payline.com/V4/services/DirectPaymentAPI'
      }
      
      LIVE_URLS = {
        :web    => 'https://services.payline.com/V4/services/WebPaymentAPI',
        :direct => 'https://services.payline.com/V4/services/DirectPaymentAPI'
      }
      
      ACTIONS_APIS = {
        'doWebPayment'          => :web,
        'getWebPaymentDetails'  => :web,
        'doAuthorization'       => :direct,
        'doCapture'             => :direct
      }

      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['PT']

      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master]

      # The homepage URL of the gateway
      self.homepage_url = 'http://www.redunicre.pt/'

      # The name of the gateway
      self.display_name = 'Redunicre'
      
      CURRENCY_CODES = {
        'USD' => 840,
        'EUR' => 978,
        'GBP' => 826
      }
      
      LANGUAGES = {
        'FR' => 'fre',
        'DE' => 'ger',
        'EN' => 'eng',
        'ES' => 'spa',
        'IT' => 'ita',
        'PT' => 'por'
      }
      
      COUNTRIES = {
        'FR' => 'FRANCE',
        'DE' => 'GERMANY',
        'GB' => 'UNITED KINGDOM',
        'ES' => 'SPAIN',
        'IT' => 'ITALY',
        'PT' => 'PORTUGAL'
      }
      
      ENVELOPE_ATTRIBUTES = {
        'xmlns:SOAP-ENV'  => "http://schemas.xmlsoap.org/soap/envelope/",
        'xmlns:ns1'       => "http://obj.ws.payline.experian.com", #ns1
        'xmlns:xsi'       => "http://www.w3.org/2001/XMLSchema-instance",
        'xmlns:ns2'       => "http://impl.ws.payline.experian.com" #ns2
      }
      
      CARD_TYPES = {
        "VISA" => "VISA",
        "MASTERCARD" => "MASTERCARD"
      }

      def initialize(options = {})
        requires!(options, :merchant_id, :access_key, :contract_number)
        @options = options
        super
      end

      def setup_payment(money, currency, options = {})
        @options.has_key?(:return_url) || requires!(options, :return_url)
        @options.has_key?(:cancel_url) || requires!(options, :cancel_url)
        @options.has_key?(:notification_url) || requires!(options, :notification_url)
        
        requires!(options, :order_ref)

        commit 'doWebPayment', build_web_payment_request(101, 'CPT', money, currency, options)
      end
      
      def details_for(token)        
        commit 'getWebPaymentDetails', build_web_payment_details_request(token)
      end
      
      #def do_authorization(money, options = {})
      #  requires!(options, :order_ref, :card)
      #  requires!(options[:card], :number, :cvx, :expiration_date, :type)
      #
      #  commit 'doAuthorization', build_authorization_request(101, 'CPT', money, 'EUR', options)
      #end
      #
      #def do_capture(money, transaction_id, options = {})
      #  commit 'doCapture', build_capture_request(transaction_id, money, 'EUR', 201, 'CPT', options)
      #end

      private
      
      def build_web_payment_details_request(token)
        xml = Builder::XmlMarkup.new
        xml.ns2 :getWebPaymentDetailsRequest do
          xml.ns2 :token, token
        end
        xml.target!
      end
      
      def build_web_payment_request(action, mode, money, currency, options)
        xml = Builder::XmlMarkup.new
        xml.ns2 :doWebPaymentRequest do
          add_payment(xml, money, currency, action, mode)
          add_order(xml, options, money, currency)
          add_selected_contract_list(xml)
          add_buyer(xml, options[:buyer])
          
          xml.ns2 :returnURL, options[:return_url] || @options[:return_url]
          xml.ns2 :cancelURL, options[:cancel_url] || @options[:cancel_url]
          xml.ns2 :notificationURL, options[:notification_url] || @options[:notification_url]
          xml.ns2 :languageCode, 'eng'
          xml.ns2 :securityMode, 'SSL'
          
          #xml << %Q|<ns2:customPaymentPageCode/>
          #<ns2:recurring xsi:nil="true"/>
          #<ns2:customPaymentTemplateURL/>|
          
          #xml.ns2 "recurring", nil
          #xml.ns2 :customPaymentPageCode
          #xml.ns2 :customPaymentTemplateURL
        end
        xml.target!
      end
      
      def add_payment(xml, money, currency, action, mode)
        xml.ns2 :payment do
          xml.ns1 :amount,              money
          xml.ns1 :currency,            CURRENCY_CODES[currency]
          xml.ns1 :action,              action
          xml.ns1 :mode,                mode
          xml.ns1 :contractNumber,      @options[:contract_number]
          #xml << %Q|<ns1:differedActionDate xsi:nil="true"/>|
          #xml.ns1 :differedActionDate,  nil
        end
      end
      
      def add_order(xml, options, money, currency)
        xml.ns2 :order do
          xml.ns1 :ref,       options[:order_ref]
          xml.ns1 :amount,    money
          xml.ns1 :currency,  CURRENCY_CODES[currency]
          xml.ns1 :date,      Time.now.strftime("%d/%m/%Y %H:%M")
          
          #xml << %Q|<ns1:origin xsi:nil="true"/>
  				#<ns1:country xsi:nil="true"/>
  				#<ns1:taxes xsi:nil="true"/>|
  				#
  				#xml << %Q|<ns1:details>
  				#	<ns1:details>
  				#		<ns1:ref xsi:nil="true"/>
  				#		<ns1:price xsi:nil="true"/>
  				#		<ns1:quantity xsi:nil="true"/>
  				#		<ns1:comment xsi:nil="true"/>
  				#	</ns1:details>
  				#	<ns1:details>
  				#		<ns1:ref xsi:nil="true"/>
  				#		<ns1:price xsi:nil="true"/>
  				#		<ns1:quantity xsi:nil="true"/>
  				#		<ns1:comment xsi:nil="true"/>
  				#	</ns1:details>
  				#</ns1:details>|
          
          #xml.ns1 :origin,    nil
          #xml.ns1 :country,   nil
          #xml.ns1 :taxes,     nil
        end
      end
      
      def add_selected_contract_list(xml)
        xml.ns2 :selectedContractList #do
          #xml.ns1 :selectedContract, nil
        #end
      end
      
      def add_buyer(xml, buyer)
        xml.ns2 :buyer do
          xml.ns1 :lastName,  buyer[:last_name]
          xml.ns1 :firstName, buyer[:first_name]
          xml.ns1 :email,     buyer[:email]
          
          xml.ns1 :shippingAdress do
            xml.ns1 :name,      nil
  					xml.ns1 :street1,   nil
  					xml.ns1 :street2,   nil
  					xml.ns1 :cityName,  nil
  					xml.ns1 :zipCode,   nil
  					xml.ns1 :country,   nil
  					#xml.ns1 :phone,     nil
          end
        #  
        #  xml.ns1 :accountCreateDate,     Time.now.strftime("%d/%m/%y")
        #  xml.ns1 :accountAverageAmount,  nil
        #  xml.ns1 :accountOrderCount,     nil
        #  xml.ns1 :walletId,              nil
        #  xml.ns1 :ip,                    nil
        end
      end
      
      def add_card(xml, options)
        xml.ns2 :card do
          xml.ns1 :number,            options[:card][:number]
          xml.ns1 :type,              CARD_TYPES[options[:card][:type]]
          xml.ns1 :expirationDate,    options[:card][:expiration_date]
          xml.ns1 :cvx,               options[:card][:cvx]
          
          #xml << %Q|<ns1:ownerBirthdayDate xsi:nil="true"/>
  				#<ns1:password xsi:nil="true"/>
  				#<ns1:cardPresent xsi:nil="true"/>|
          
          #xml.ns1 "ownerBirthdayDate", nil
          #xml.ns1 "password",          nil
          #xml.ns1 "cardPresent",       nil
        end
      end
      
      def add_private_data_list(xml)
        xml.ns2 :privateDataList
        #xml << %Q|<ns2:privateDataList>
  			#	<ns1:privateData>
  			#		<ns1:key/>
  			#		<ns1:value/>
  			#	</ns1:privateData>
  			#	<ns1:privateData>
  			#		<ns1:key/>
  			#		<ns1:value/>
  			#	</ns1:privateData>
  			#	<ns1:privateData>
  			#		<ns1:key/>
  			#		<ns1:value/>
  			#	</ns1:privateData>
  			#</ns2:privateDataList>|
      end
      
      def add_authentication_3d_secure(xml)
        xml.ns2 :authentication3DSecure
        #xml << %Q|<ns2:authentication3DSecure>
  			#	<ns1:md xsi:nil="true"/>
  			#	<ns1:pares xsi:nil="true"/>
  			#	<ns1:xid xsi:nil="true"/>
  			#	<ns1:eci xsi:nil="true"/>
  			#	<ns1:cavv xsi:nil="true"/>
  			#	<ns1:cavvAlgorithm xsi:nil="true"/>
  			#	<ns1:vadsResult xsi:nil="true"/>
  			#	<ns1:typeSecurisation xsi:nil="true"/>
  			#</ns2:authentication3DSecure>|
      end
      
      def build_capture_request(transaction_id, money, currency, action, mode, options)
        xml = Builder::XmlMarkup.new
          xml.ns2 :doCaptureRequest do
            xml.ns2 :transactionID, transaction_id
            add_payment(xml, money, currency, action, mode)
            add_private_data_list(xml)
            xml << %Q|<ns1:sequenceNumber/>|
          end
        xml.target!
      end
      
      def build_authorization_request(action, mode, money, currency, options)
        xml = Builder::XmlMarkup.new
        xml.ns2 :doAuthorizationRequest do
          add_payment(xml, money, currency, action, mode)
          add_card(xml, options)
          add_order(xml, options, money, currency)
          add_buyer(xml)
          add_private_data_list(xml)
          add_authentication_3d_secure(xml)
        end
        xml.target!
      end
      
      def build_request(body)
        xml = Builder::XmlMarkup.new
        
        xml.instruct!
        
        xml.tag! "SOAP-ENV:Envelope", ENVELOPE_ATTRIBUTES do
          xml.tag! "SOAP-ENV:Body" do
            xml << body
          end
        end
        
        xml.target!
      end
      
      def endpoint_url(action)
        if test?
          TEST_URLS[ACTIONS_APIS[action]]
        else
          LIVE_URLS[ACTIONS_APIS[action]]
        end
      end
      
      def encoded_credentials
        credentials = [@options[:merchant_id], @options[:access_key]].join(':')
        return Base64.encode64(credentials).strip
      end
      
      def request_headers(action)
        {
          'Authorization' => "Basic #{encoded_credentials}",
          'SOAPAction'    => "\"#{action}\"",
          "Content-Type"  => "text/xml; charset=utf-8"
        }
      end

      def commit(action, request)
        response = parse(action, ssl_post(endpoint_url(action), build_request(request), request_headers(action)))

        build_response(successful?(response), message_from(response), response,
          :test => test?,
          :duplicated => is_duplicated?(response),
          :is_fraud => fraud_review?(response)
        )
      end
      
      def build_response(success, message, response, options = {})
         Response.new(success, message, response, options)
      end
      
      def successful?(response)
        response[:code] == "00000"
      end
      
      def is_duplicated?(response)
        response[:is_duplicated] == "1"
      end
      
      def fraud_review?(response)
        response[:is_possible_fraud] == "1"
      end
      
      def message_from(response)
        response[:short_message] || response[:long_message]
      end
      
      def parse_element(response, node)
        if node.has_elements?
          node.elements.each{|e| parse_element(response, e) }
        else
          response[node.name.underscore.to_sym] = node.text
          node.attributes.each do |k, v|
            response["#{node.name.underscore}_#{k.underscore}".to_sym] = v if k == 'currencyID'
          end
        end
      end
      
      def parse(action, xml)          
        response = {}
        
        error_messages = []
        error_codes = []
        
        xml = REXML::Document.new(xml)
        if root = REXML::XPath.first(xml, "//#{action}Response")
          root.elements.each do |node|            
            case node.name
            when 'Errors'
              short_message = nil
              long_message = nil
              
              node.elements.each do |child|
                case child.name
                when "LongMessage"
                  long_message = child.text unless child.text.blank?
                when "ShortMessage"
                  short_message = child.text unless child.text.blank?
                when "ErrorCode"
                  error_codes << child.text unless child.text.blank?
                end
              end

              if message = long_message || short_message
                error_messages << message
              end
            else
              parse_element(response, node)
            end
          end
          response[:message] = error_messages.uniq.join(". ") unless error_messages.empty?
          response[:error_codes] = error_codes.uniq.join(",") unless error_codes.empty?
        elsif root = REXML::XPath.first(xml, "//SOAP-ENV:Fault")
          parse_element(response, root)
          response[:message] = "#{response[:faultcode]}: #{response[:faultstring]} - #{response[:detail]}"
        end
        
        response
      end
    end
  end
end