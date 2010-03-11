require 'base64'

module ActiveMerchant
  module Billing
    class RedunicreWebGateway < Gateway

      TEST_URL = 'https://homologation.payline.com/V4/services/WebPaymentAPI'
      LIVE_URL = 'https://services.payline.com/V4/services/WebPaymentAPI'
      LIVE_REDIRECT_URL = 'http://change.me.at.line.number.7.redunicre_web.rb.com'
      TEST_REDIRECT_URL = 'http://change.me.at.line.number.8.redunicre_web.rb.com'

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
        'xmlns:ns2'      => "http://impl.ws.payline.experian.com" #ns2
      }

      def initialize(options = {})
        requires!(options, :merchant_id, :access_key, :contract_number)
        @options = options
        super
      end

      def redirect_url
        test? ? TEST_REDIRECT_URL : LIVE_REDIRECT_URL
      end

      def redirect_url_for(token)
        "#{redirect_url}#{token}"
      end

      def setup_purchase(money, options = {})
        requires!(options, :return_url, :cancel_url, :order_ref, :notification_url)

        commit 'doWebPayment', build_web_payment_request(101, 'CPT', money, 'USD', options)
      end

      private
      
      def add_payment(xml, money, currency, action, mode)
        xml.ns2 :payment do
          xml.ns1 :amount,              money
          xml.ns1 :currency,            CURRENCY_CODES[currency]
          xml.ns1 :action,              action
          xml.ns1 :mode,                mode
          xml.ns1 :contractNumber,      @options[:contract_number]
          xml.ns1 :differedActionDate,  nil
        end
      end
      
      def add_order(xml, options, money, currency)
        xml.ns2 :order do
          xml.ns1 :ref,       options[:order_ref]
          xml.ns1 :amount,    money
          xml.ns1 :currency,  CURRENCY_CODES[currency]
          xml.ns1 :date,      Time.now.strftime("%d/%m/%Y %H:%M")
          xml.ns1 :origin,    nil
          xml.ns1 :country,   nil
          xml.ns1 :taxes,     nil
        end
      end
      
      def add_selected_contract_list(xml)
        xml.ns2 :selectedContractList do
          xml.ns1 :selectedContract, @options[:contract_number]
        end
      end
      
      def add_buyer(xml)
        xml.ns2 :buyer do
          xml.ns1 :lastName,  nil
          xml.ns1 :firstName, nil
          xml.ns1 :email,     nil
          
          xml.ns1 :shippingAdress do
            xml.ns1 :name,      nil
  					xml.ns1 :street1,   nil
  					xml.ns1 :street2,   nil
  					xml.ns1 :cityName,  nil
  					xml.ns1 :zipCode,   nil
  					xml.ns1 :country,   nil
  					xml.ns1 :phone,     nil
          end
          
          xml.ns1 :accountCreateDate,     Time.now.strftime("%d/%m/%y")
          xml.ns1 :accountAverageAmount,  nil
          xml.ns1 :accountOrderCount,     nil
          xml.ns1 :walletId,              nil
          xml.ns1 :ip,                    nil
        end
      end

      def build_web_payment_request(action, mode, money, currency, options)
        xml = Builder::XmlMarkup.new
        xml.ns2 :doWebPaymentRequest do
          add_payment(xml, money, currency, action, mode)
          add_order(xml, options, money, currency)
          add_selected_contract_list(xml)
          add_buyer(xml)
          
          xml.ns2 :returnURL, options[:return_url]
          xml.ns2 :cancelURL, options[:cancel_url]
          xml.ns2 :notificationURL, options[:notification_url]
          xml.ns2 :languageCode, 'eng'
          xml.ns2 :securityMode, 'SSL'
          xml.ns2 :recurring, nil
          xml.ns2 :customPaymentPageCode
          xml.ns2 :customPaymentTemplateURL
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
      
      def endpoint_url
        test? ? TEST_URL : LIVE_URL
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
        puts build_request(request)
        puts "=============="
        puts request_headers(action).inspect
        puts "=============="
        puts ssl_post(endpoint_url, build_request(request), request_headers(action))
        response = parse(action, ssl_post(endpoint_url, build_request(request), request_headers(action)))
        
        #build_response(successful?(response), message_from(response), response,
        #:test => test?,
        #:authorization => authorization_from(response),
        #:fraud_review => fraud_review?(response),
        #:avs_result => { :code => response[:avs_code] },
        #:cvv_result => response[:cvv2_code]
        #)
      end
      
      #def successful?(response)
      #  SUCCESS_CODES.include?(response[:ack])
      #end
      #
      #def message_from(response)
      #  response[:message] || response[:ack]
      #end
      
      #def parse(body)
      #  body
      #end
    end
  end
end