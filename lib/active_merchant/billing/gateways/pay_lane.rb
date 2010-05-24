module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayLaneGateway < Gateway
      TEST_URL = 'https://direct.paylane.com/soapserver/direct.php'
      LIVE_URL = 'https://direct.paylane.com/soapserver/direct.php'

      # ISO 4217 codes
      CURRENCY_CODES = ['USD', 'EUR']

      ENVELOPE_ATTRIBUTES = {
        "xmlns:SOAP-ENV"  => "http://schemas.xmlsoap.org/soap/envelope/",
        "xmlns:ns1"       => "http://www.paylane.com/Direct.wsdl"
      }

      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['PT']

      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master]

      # The homepage URL of the gateway
      self.homepage_url = 'http://www.paylane.com/'

      # The name of the gateway
      self.display_name = 'PayLane'

      def initialize(options = {})
        requires!(options, :login, :password)
        @options = options
        super
      end

      # should call 'multiSale' with capture_later = true
      def authorize(money, currency, options = {})
        requires!(options, :product, :payment, :customer)

        commit 'multiSale', build_multiSale_request(money, currency, options.merge({:capture_later => true}))
      end

      # should call 'captureSale'
      def capture(sale_id, money, options = {})
        description = options[:description] || ""

        commit('captureSale', build_captureSale_request(sale_id, money, description))
      end

      # should call 'multiSale' with capture_later = false
      def purchase(money, currency, options = {})
        commit 'multiSale', build_multiSale_request(money, currency, options.merge({:capture_later => false}))
      end

      # should call 'closeSaleAuthorization'
      def cancel_authorization(sale_id)
        commit 'closeSaleAuthorization', build_closeSaleAuthorization_request(sale_id)
      end

      # should call 'refund'
      def refund(sale_id)
        raise "Not Implemented"
        #commit 'refund'
      end

      # should call 'resale'
      def rebill(sale_id, money, currency, options = {})
        requires!(options, :card_code)
        description = options[:description] || ""
        
        commit 'resale', build_resale_request(sale_id, money, currency, description, options[:card_code])
      end

      private

      def build_resale_request(sale_id, money, currency, description, card_code)
        xml = Builder::XmlMarkup.new
        xml.ns1 :resale do
          xml.tag! :id_sale, sale_id
          xml.tag! :amount, money
          xml.tag! :currency, currency
          xml.tag! :card_code, card_code
          xml.tag! :description, description
        end
        xml.target!
      end

      def build_captureSale_request(sale_id, money, description)
        xml = Builder::XmlMarkup.new
        xml.ns1 :captureSale do
          xml.tag! :id_sale_authorization, sale_id
          xml.tag! :amount, money
          xml.tag! :description, description
        end
        xml.target!
      end

      def build_closeSaleAuthorization_request(sale_id)
        xml = Builder::XmlMarkup.new
        xml.ns1 :closeSaleAuthorization do
          xml.tag! :id_sale_authorization, sale_id
        end
        xml.target!
      end

      def build_multiSale_request(money, currency, options)
        xml = Builder::XmlMarkup.new
        xml.ns1 :multiSale do
          xml.tag! :params do
            xml.tag! :capture_later, options[:capture_later]
            xml.tag! :amount,        money
            xml.tag! :currency_code, currency

            add_payment_method_data(xml, options[:payment])
            add_product_data(xml, options[:product])
            add_customer_data(xml, options[:customer])
          end
        end
        xml.target!
      end

      def add_payment_method_data(xml, card)
        xml.tag! :payment_method do
          xml.tag! :card_data do
            xml.tag! :card_number,       card[:number]
            xml.tag! :card_code,         card[:code]     # CVV2, CVC2, CID
            xml.tag! :expiration_month,  card[:month]
            xml.tag! :expiration_year,   card[:year]
            xml.tag! :name_on_card,      card[:name]
            xml.tag! :issue_number,      card[:maestro_issue] if card[:maestro_issue]
          end
        end
      end

      def add_product_data(xml, product)
        xml.tag! :product do
          xml.tag! :description, product[:description]
        end
      end

      def add_customer_data(xml, customer)
        xml.tag! :customer do
          xml.tag! :name,    customer[:name]
          xml.tag! :email,   customer[:email]
          xml.tag! :ip,      customer[:ip]
          xml.tag! :address do
            xml.tag! :street_house,  customer[:address][:street_and_number]
            xml.tag! :city,          customer[:address][:city]
            xml.tag! :state,         customer[:address][:state] if customer[:address][:state]
            xml.tag! :zip,           customer[:address][:zip]
            xml.tag! :country_code,  customer[:address][:country_code]
          end
        end
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

      def endpoint_url(action = "")
        if test?
          TEST_URL
        else
          LIVE_URL
        end
      end

      def encoded_credentials
        credentials = [@options[:login], @options[:password]].join(':')
        return Base64.encode64(credentials).strip
      end

      def request_headers(action, length = 0)
        {
          'Authorization'   => "Basic #{encoded_credentials}",
          'SOAPAction'      => "\"http://www.paylane.com/Direct.wsdl/#{action}\"",
          "Content-Type"    => "text/xml; charset=utf-8",
          "Content-Length"  => length.to_s
        }
      end

      def commit(action, request)
        request = build_request(request)
        headers = request_headers(action, request.size)

        resp_body = ssl_post(endpoint_url, request, headers)
        response = parse(action, resp_body)
        
        Response.new(successful?(response), message_from(response), response[:DATA]||{})
      end

      def successful?(response)
        !!response[:OK]
      end

      def message_from(response)
        response[:OK] || response[:ERROR]
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
