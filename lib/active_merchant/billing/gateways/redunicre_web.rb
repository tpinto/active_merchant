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

        commit 'doWebPayment', build_setup_request(101, 'CPT', money, 'USD', options)
      end

      private

      def build_setup_request(action, mode, money, currency, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'doWebPaymentRequest' do
          xml.tag! 'Payment' do
            xml.tag! 'Amount', money
            xml.tag! 'Currency', CURRENCY_CODES[currency]
            xml.tag! 'Action', action
            xml.tag! 'Mode', mode
            xml.tag! 'ContractNumber', @options[:contract_number]
          end
          xml.tag! 'Order' do
            xml.tag! 'Ref', options[:order_ref]
            xml.tag! 'Amount', money
            xml.tag! 'Currency', CURRENCY_CODES[currency]
            xml.tag! 'Date', Date.today
          end
          xml.tag! 'ReturnURL', options[:return_url]
          xml.tag! 'CancelURL', options[:cancel_url]
          xml.tag! 'NotificationURL', options[:notification_url]
          xml.tag! 'SecurityMode', 'SSL'
          xml.tag! 'LanguageCode', LANGUAGES['EN']
        end
      end
      
      def build_request(body)
        xml = Builder::XmlMarkup.new
        
        xml.instruct!
        xml.tag! 'env:Envelope' do
          xml.tag! 'env:Body' do
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
      
      def request_headers
        {
          'Authorization' => "Basic #{encoded_credentials}"
        }
      end

      def commit(action, request)
        response = parse(action, ssl_post(endpoint_url, build_request(request), headers))
        
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
      
      def parse(body)
        body
      end
      
      def post_data(action, parameters = {})
      end
    end
  end
end