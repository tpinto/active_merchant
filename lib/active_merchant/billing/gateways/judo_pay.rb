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
        #requires!(options, :login, :password)
        super
      end

      def authorize(money, creditcard, options = {})
        if creditcard.is_a?(ActiveMerchant::Billing::CreditCard)
          post = {
            yourConsumerReference: "consumer0053252",
            yourPaymentReference: "payment12412312",
            yourPaymentMetaData: {
               any: "value"
            },
            judoId: "1234-4567",
            amount: 12.34,
            cardNumber: "4976000000003436",
            expiryDate: "12/15",
            cv2: "452",
            cardAddress: {
               line1: "242 Acklam Road",
               line2: "Westbourne Park",
               line3: "",
               town: "London",
               postCode: "W10 5JJ"
            },
            consumerLocation: {
               latitude: 51.5214541344954,
               longitude: -0.203098409696038
            },
            mobileNumber: "07100000000",
            emailAddress: "cardholder@test.com"
          }
        elsif creditcard.is_a?(String)
          post = {
            yourConsumerReference: "consumer0053252",
            yourPaymentReference: "payment12412312",
            yourPaymentMetaData: {
               any: "value"
            },
            judoId: "1234-4567",
            amount: 12.34,
            consumerToken: "3UW4DV9wI0oKkMFS",
            cardToken: creditcard,
            cv2: "452",
            consumerLocation: {
               latitude: 51.5214541344954,
               longitude: -0.203098409696038
            },
            mobileNumber: "07100000000",
            emailAddress: "cardholder@test.com"
          }
        else
          raise "creditcard option should be either a CreditCard or a String."
        end

        commit(:post, 'preauths', post)
      end

      def purchase(money, creditcard, options = {})
        post = {
          yourConsumerReference: "consumer0053252",
          yourPaymentReference: "payment12412312",
          yourPaymentMetaData: {
             any: "value"
          },
          judoId: "1234-4567",
          amount: 12.34,
          consumerToken: "3UW4DV9wI0oKkMFS",
          cardToken: "SXw4hnv1vJuEujQR",
          cv2: "452",
          consumerLocation: {
             latitude: 51.5214541344954,
             longitude: -0.203098409696038
          },
          mobileNumber: "07100000000",
          emailAddress: "cardholder@test.com"
        }

        commit('payments', money, post)
      end

      def capture(money, authorization, options = {})
        post = {
          receiptId: "123456",
          amount: 12.34,
          yourPaymentReference: "payment12412312"
        }

        commit('collections', money, post)
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
      #end

      def headers(options = {})
        {
          "Authorization" => "Basic " + Base64.encode64(key.to_s + ":").strip,
          "User-Agent" => "judoPay ActiveMerchantBindings/#{ActiveMerchant::VERSION}",
          "X-Stripe-Client-User-Agent" => @@ua,
          "X-Stripe-Client-User-Metadata" => options[:meta].to_json
        }
      end

      def parse(body)
        JSON.parse(body)
      end

      def commit(method, url, parameters=nil, options = {})
        raw_response = response = nil
        success = false
        begin
          raw_response = ssl_request(method, self.live_url + url, post_data(parameters), headers(options))
          response = parse(raw_response)
          success = !response.key?("error")
        rescue ResponseError => e
          raw_response = e.response.body
          response = response_error(raw_response)
        rescue JSON::ParserError
          response = json_error(raw_response)
        end

        card = response["card"] || response["active_card"] || {}
        avs_code = AVS_CODE_TRANSLATOR["line1: #{card["address_line1_check"]}, zip: #{card["address_zip_check"]}"]
        cvc_code = CVC_CODE_TRANSLATOR[card["cvc_check"]]
        Response.new(success,
          success ? "Transaction approved" : response["error"]["message"],
          response,
          :test => response.has_key?("livemode") ? !response["livemode"] : false,
          :authorization => response["id"],
          :avs_result => { :code => avs_code },
          :cvv_result => cvc_code
        )
      end

      def response_error(raw_response)
        begin
          parse(raw_response)
        rescue JSON::ParserError
          json_error(raw_response)
        end
      end

      def json_error(raw_response)
        msg = 'Invalid response received from the Stripe API.  Please contact support@stripe.com if you continue to receive this message.'
        msg += "  (The raw response returned by the API was #{raw_response.inspect})"
        {
          "error" => {
            "message" => msg
          }
        }
      end

      def post_data(action, parameters = {})
        return nil unless parameters

        parameters.map do |key, value|
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
    end
  end
end

