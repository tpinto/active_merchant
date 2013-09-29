module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class JudoPayGateway < Gateway
      self.live_url = 'https://partnerapi.judopay.com'
      self.test_url = 'https://partnerapi.judopay-sandbox.com'

      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['GB']

      self.default_currency = 'GBP'

      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master]

      # The homepage URL of the gateway
      self.homepage_url = 'https://www.judopay.com/'

      # The name of the gateway
      self.display_name = 'judoPay'

      def initialize(options = {})
        requires!(options, :token, :secret, :judo_id)

        @api_token = options[:token]
        @api_secret = options[:secret]
        @api_judo_id = options[:judo_id]

        super
      end

      def judo_id
        options[:merchant] || @api_judo_id
      end

      def authorize(money, creditcard, options = {})
        requires!(options, :customer, :order_id)

        if creditcard.is_a?(ActiveMerchant::Billing::CreditCard)
          post = {
            yourConsumerReference: options[:customer],
            yourPaymentReference: options[:order_id],
            judoId: judo_id,
            amount: money,
            cardNumber: creditcard.number,
            expiryDate: "#{creditcard.month}/#{creditcard.year}",
            cv2: creditcard.verification_value
          }
        elsif creditcard.is_a?(String)
          requires!(options, :judo_consumer_token, :cv2)

          post = {
            yourConsumerReference: options[:customer],
            yourPaymentReference: options[:order_id],
            judoId: judo_id,
            amount: money,
            consumerToken: options[:judo_consumer_token],
            cardToken: creditcard,
            cv2: options[:cv2]
          }
        else
          raise "creditcard should be either a CreditCard object or a String."
        end

        commit(:post, '/transactions/preauths', post)
      end

      def purchase(money, creditcard, options = {})
        requires!(options, :customer, :order_id)

        if creditcard.is_a?(ActiveMerchant::Billing::CreditCard)
          post = {
            yourConsumerReference: options[:customer],
            yourPaymentReference: options[:order_id],
            judoId: judo_id,
            amount: money,
            cardNumber: creditcard.number,
            expiryDate: "#{creditcard.month}/#{creditcard.year}",
            cv2: creditcard.verification_value
          }
        elsif creditcard.is_a?(String)
          requires!(options, :judo_consumer_token, :cv2)

          post = {
            yourConsumerReference: options[:customer],
            yourPaymentReference: options[:order_id],
            judoId: judo_id,
            amount: money,
            consumerToken: options[:judo_consumer_token],
            cardToken: creditcard,
            cv2: options[:cv2]
          }
        else
          raise "creditcard should be either a CreditCard object or a String."
        end

        commit(:post, '/transactions/payments', post)
      end

      def capture(money, authorization, options = {})
        requires!(options, :order_id)

        post = {
          receiptId: authorization,
          amount: money,
          yourPaymentReference: options[:order_id]
        }

        commit(:post, '/transactions/collections', post)
      end

      def transactions(options = {})
        post = merge_defaults options, {
          sort: 'time-descending',
          offset: 0,
          pageSize: 10
        }
        commit(:get, '/transactions', options)
      end

      def refund(money, identification, options = {})
        requires!(options, :order_id)

        post = {
          receiptId: identification,
          amount: money,
          yourPaymentReference: options[:order_id]
        }

        commit(:post, '/transactions/refunds', post)
      end

      private

      #def add_local_references_and_metadata(post, options)
      #  post[:yourConsumerReference] = options[:customer_id]
      #  post[:yourPaymentReference] = options[:id]
      #  post[:yourPaymentMetaData] = options[:meta_data]
      #end
#
      #def add_location(post, options)
      #  post["consumerLocation"] = options[:location]
      #end
#
      #def add_customer_data(post, options)
      #  post["mobileNumber"] = options[:customer_phone]
      #  post["emailAddress"] = options[:customer_email]
      #end
#
      #def add_address(post, options)
      #  post["cardAddress"] = options[:address]
#
      #  #{
      #  #  "line1": "242 Acklam Road",
      #  #  "line2": "Westbourne Park",
      #  #  "town": "London",
      #  #  "postCode": "W10 5JJ"
      #  #}
      #end
#
      #def add_creditcard(post, creditcard)
      #  post["cardNumber"] = creditcard[:number]
      #  post["expiryDate"] = creditcard[:expiry]
      #  post["cv2"] = creditcard[:code]
      #endp

      def merge_defaults(hash, defs)
        hash.merge(defs) { |key, old, new| old.nil? ? new : old }
      end

      def url
        test? ? self.test_url : self.live_url
      end

      def headers
        {
          "Authorization" => "Basic "+Base64.encode64(@api_token+":"+@api_secret).gsub(/\n/, ''),
          "Accept" => "application/json",
          "API-Version" => "2.0.0.0",
          "Content-Type" => "application/json"
        }
      end

      def parse(body)
        JSON.parse(body)
      end

      def post_data(params)
        return nil unless params

        params.map do |key, value|
          next if value.blank?
          if value.is_a?(Hash)
            h = {}
            value.each do |k, v|
              h["#{key}[#{k}]"] = v unless v.blank?
            end
            post_data(h)
          else
            "#{key}=#{CGI.escape(value.to_s)}"
          end
        end.compact.join("&")
      end

      def commit(method, path, post = {})
        raw_response = response = nil
        success = false
        begin
          case method
          when :post
            raw_response = ssl_post(url+path, post.to_json, headers)
          when :get
            raw_response = ssl_get(url+path+"?"+post_data(post), headers)
          end
          
          response = parse(raw_response)
          success = response['result'] == 'Success'
        rescue ResponseError => e
          raw_response = e.response.body
          response = response_error(raw_response)
        #rescue JSON::ParserError
        #  response = json_error(raw_response)
        #end
        rescue => e
          puts e.inspect
          puts "req to: " + url + path
          puts "json: " + post.to_json
          puts "headers: " + headers.inspect
          puts "resp: " + raw_response.inspect
        end

        Response.new(success,
            success ? response['message'] : response['errorMessage'],
            response,
            :test => test?,
            :authorization => response["receiptId"])
      end

      def response_error(raw_response)
        begin
          parse(raw_response)
        rescue JSON::ParserError
          json_error(raw_response)
        end
      end
#
      #def json_error(raw_response)
      #  msg = 'Invalid response received from the Stripe API.  Please contact support@stripe.com if you continue to receive this message.'
      #  msg += "  (The raw response returned by the API was #{raw_response.inspect})"
      #  {
      #    "error" => {
      #      "message" => msg
      #    }
      #  }
      #end
    end
  end
end

