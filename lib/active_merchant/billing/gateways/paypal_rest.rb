begin
  require "paypal-sdk-rest"
  raise "Please update paypal-sdk-rest gem to >= 0.6.0" if PayPal::SDK::REST::VERSION < '0.6.0'
rescue LoadError
  raise "Install paypal-sdk-rest gem, to use PaypalRestGateway"
end
require 'cgi'

module ActiveMerchant
  module Billing

    # Gateway for PayPal REST APIs.
    # == Example
    #
    #   # Configure credentials
    #   @gateway = ActiveMerchant::Billing::PaypalRestGateway.new(
    #     :mode => "sandbox",
    #     :client_id => "ABC",
    #     :client_secret => "XYZ"
    #   )
    #
    #   # Create credit card object to make payment
    #   credit_card = ActiveMerchant::Billing::CreditCard.new(
    #     :brand              => 'visa',
    #     :first_name         => 'Bob',
    #     :last_name          => 'Bobsen',
    #     :number             => '4242424242424242',
    #     :month              => '8',
    #     :year               => Time.now.year+1,
    #     :verification_value => '000')
    #
    #   response = @gateway.purchase(1000, credit_card)
    #
    #   if response.success?
    #     puts response.params
    #   else
    #     puts response.message
    #   end
    #
    # === Supported options
    # * <tt>currency</tt> - Default currency (USD)
    # * <tt>tax</tt>      - Tax amount
    # * <tt>shipping</tt> - Shipping amount
    # * <tt>subtotal</tt> - Items total amount
    # * <tt>fee</tt>      - Fee amount
    # * <tt>items</tt>    - Array of item( :name, :quantity, :price )
    # * <tt>header</tt>   - HTTP header
    # * <tt>request_id</tt> - Unique ID for the API request.
    #
    # * <tt>billing_address</tt>  - Billing Address for credit_card payment
    # * <tt>shipping_address</tt> - Shipping address for purchase and authorize calls
    #
    # * <tt>payer_id</tt> - For execute call
    # * <tt>is_final_capture</tt> - For capture call
    class PaypalRestGateway < Gateway


      class API < PayPal::SDK::Core::API::REST
        def self.user_agent
          @user_agent ||= "PayPalSDK/rest-sdk-activemerchant #{ActiveMerchant::VERSION} (#{sdk_library_details})"
        end
      end

      class Response < Billing::Response
        def id
          params["id"]
        end

        def state
          params["state"]
        end

        def authorization
          params["transactions"][0]["related_resources"][0]["authorization"] rescue nil
        end

        def authorization_id
          authorization ? authorization["id"] : nil
        end

        def sale
          params["transactions"][0]["related_resources"][0]["sale"] rescue nil
        end

        def sale_id
          sale ? sale["id"] : nil
        end

        def approval_url
          params["links"].find{|link| link["rel"] == "approval_url" }["href"] rescue nil
        end
        alias_method :redirect_url, :approval_url

      end

      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.homepage_url = 'http://developer.paypal.com'
      self.display_name = 'PayPal Payments'

      API_OPTIONS = [ :mode, :client_id, :client_secret, :ssl_options ]

      # Interface object for PayPal REST Api
      def api
        @api ||=
          begin
            api_options = options.select{|k,v| API_OPTIONS.include? k }
            API.new(api_options)
          end
      end


      # Create payment with credit-card, credit-card-token or paypal
      # === Arguments
      # * <tt>money</tt> - In cents
      # * <tt>credit_card</tt> - CreditCard object or CreditCard Token
      # * <tt>options</tt> - (Optional) `items`, `billing_address` and `shipping_address` are supported.
      # === Example
      #   # with credit-card object
      #   response = @gateway.purchase(1000, credit_card)
      #
      #   # with credit-card-token
      #   response = @gateway.purchase(1000, "CARD-XXXX")
      #
      #   # with paypal
      #   response = @gateway.purchase(1000,
      #     :return_url => "http://example.com/return",
      #     :cancel_url => "http://example.com/cancel",
      #     :items => [ { :price => 1000, :quantity => 1, :name => "Item" } ] )
      #
      #   # check response status
      #   response.success? # true or false
      #
      #   # get payment-id from response object
      #   response.params["id"]
      #
      #   # get Sale object
      #   response.sale
      def purchase(money, credit_card, options = {})
        if credit_card.is_a? Hash
          options = credit_card
        else
          options[:credit_card] = credit_card
        end
        if options[:payment_id]
          execute(money, options)
        else
          payment = build_payment(options[:intent] || "sale", money, options)
          request(:post, "v1/payments/payment", payment, options)
        end
      end

      alias_method :setup_purchase, :purchase

      # Get authorize make payment with credit-card, credit-card-token or paypal
      # === Arguments
      # * <tt>money</tt> - In cents
      # * <tt>credit_card</tt> - CreditCard object or CreditCard Token
      # * <tt>options</tt> - (Optional) `items`, `billing_address` and `shipping_address` are supported.
      # === Example
      #   # with credit-card object
      #   response = @gateway.authorize(1000, credit_card)
      #
      #   # with credit-card-token
      #   response = @gateway.authorize(1000, "CARD-XXXX")
      #
      #   # with paypal
      #   response = @gateway.authorize(1000,
      #     :return_url => "http://example.com/return",
      #     :cancel_url => "http://example.com/cancel" )
      #
      #   # check response status
      #   response.success? # true or false
      #
      #   # get Authorization object
      #   response.authorization
      def authorize(money, credit_card, options = {})
        purchase(money, credit_card, options.merge( :intent => "authorize" ))
      end

      alias_method :authorization,       :authorize
      alias_method :setup_authorize,     :authorize
      alias_method :setup_authorization, :authorize

      # Reauthorizes an expired Authorization.
      # === Arguments
      # * <tt>money</tt>
      # * <tt>options</tt> - Allowed options (authorization_id, currency)
      # === Example
      #   response = @gateway.reauthorize(100, :authorization_id => "Replace with authorization_id")
      def reauthorize(money, options = {})
        requires!(options, :authorization_id)
        payload = {
          :amount => build_amount(money, options) }
        authorization_id = CGI.escape(options[:authorization_id])
        request(:post, "v1/payments/authorization/#{authorization_id}/reauthorize", payload, options)
      end

      # Capture amount for authorize payment
      # === Arguments
      # * <tt>money</tt> - In cents
      # * <tt>options</tt> - `is_final_capture`  and `authorization_id`
      # === Example
      #   # partial capture
      #   response = @gateway.capture(5000, :authorization_id => "Replace with authorization_id", :is_final_capture => false )
      #
      #   # final capture
      #   response = @gateway.capture(5000, :authorization_id => "Replace with authorization_id", :is_final_capture => true )
      def capture(money, options = {})
        requires!(options, :authorization_id)
        transaction = {
          :amount => build_amount(money, options),
          :is_final_capture => options[:is_final_capture] }
        authorization_id = CGI.escape(options[:authorization_id])
        request(:post, "v1/payments/authorization/#{authorization_id}/capture", transaction, options)
      end

      # Execute the PayPal Payment
      # === Arguments
      # * <tt>money</tt> - In cents
      # * <tt>payment_id</tt> - Payment id
      # * <tt>options</tt> - `payer_id` is required
      # === Example
      #   # Execute payment
      #   response = @gateway.execute(1000, :payment_id => "PAY-XXXX", :payer_id => "Replace with payer_id" )
      def execute(money, options = {})
        requires!(options, :payment_id, :payer_id)
        payload = { :payer_id => options[:payer_id] }
        # FIXME: Document refer Transaction type, but actual API work with Amount type only
        payload[:transactions] = [ build_amount(money, options) ] if money
        payment_id = CGI.escape(options[:payment_id])
        request(:post, "v1/payments/payment/#{payment_id}/execute", payload, options)
      end

      # Refund purchase payment
      # === Arguments
      # * <tt>money</tt> - In cents
      # * <tt>sale_id</tt> - Sale id
      # * <tt>options</tt> - (Optional)
      # === Example
      #   # Refund for sale
      #   response = @gateway.refund(1000, :sale_id => "Replace with sale id")
      #
      #   # Refund for capture
      #   response = @gateway.refund(1000, :capture_id => "Replace with sale id")
      def refund(money, options = {})
        payload = { :amount => build_amount(money, options) }
        if options[:capture_id]
          capture_id = CGI.escape(options[:capture_id])
          request(:post, "v1/payments/capture/#{capture_id}/refund", payload, options)
        else
          requires!(options, :sale_id)
          sale_id = CGI.escape(options[:sale_id])
          request(:post, "v1/payments/sale/#{sale_id}/refund", payload, options)
        end
      end

      # Store credit-card in vault
      # === Arguments
      # * <tt>credit_card</tt> - CreditCrad
      # * <tt>options</tt> - (Optional)
      # === Example
      #   response = @gateway.store_credit_card(credit_card)
      #   if response.success?
      #     response.params["id"]
      #   end
      def store_credit_card(credit_card, options = {})
        credit_card = build_credit_card(credit_card, options)
        request(:post, "v1/vault/credit-card", credit_card, options)
      end

      # Get credit-card object
      def get_credit_card(credit_card_id, options = {})
        credit_card_id = CGI.escape(credit_card_id)
        request(:get, "v1/vault/credit-card/#{credit_card_id}", {}, options)
      end

      # Delete credit-card
      def delete_credit_card(credit_card_id, options = {})
        credit_card_id = CGI.escape(credit_card_id)
        request(:delete, "v1/vault/credit-card/#{credit_card_id}", {}, options)
      end

      # Get PaymentHistory
      # === Arguments
      # * <tt>params</tt>  - parameters( :count, next_id )
      # * <tt>options</tt> - (Optional)
      # === Example
      #   response = @gateway.payment_history( :count => 10 )
      #   if response.success?
      #     response.params["payments"]
      #   end
      def payment_history(params = {}, options = {})
        request(:get, "v1/payments/payment", params, options)
      end

      # Get Payment object
      def get_payment(payment_id, options = {})
        payment_id = CGI.escape(payment_id)
        request(:get, "v1/payments/payment/#{payment_id}", {}, options)
      end

      # Get Sale object
      def get_sale(sale_id, options = {})
        sale_id = CGI.escape(sale_id)
        request(:get, "v1/payments/sale/#{sale_id}", {}, options)
      end

      # Get Authorization object
      def get_authorization(authorization_id, options = {})
        authorization_id = CGI.escape(authorization_id)
        request(:get, "v1/payments/authorization/#{authorization_id}", {}, options)
      end

      # Void Authorization
      def void_authorization(authorization_id, options = {})
        authorization_id = CGI.escape(authorization_id)
        request(:post, "v1/payments/authorization/#{authorization_id}/void", {}, options)
      end

      # Get Capture object
      def get_capture(capture_id, options = {})
        capture_id = CGI.escape(capture_id)
        request(:get, "v1/payments/capture/#{capture_id}", {}, options)
      end

      # Get Refund object
      def get_refund(refund_id, options = {})
        refund_id = CGI.escape(refund_id)
        request(:get, "v1/payments/refund/#{refund_id}", {}, options)
      end

      private

      def request(method, path, data, options)
        http_header = build_http_header(options)
        response =
          if http_header.any?
            api.send(method, path, data, http_header)
          else
            api.send(method, path, data)
          end
        build_response(response, options)
      rescue PayPal::SDK::Core::Exceptions::ConnectionError => error
        build_response({"error" => {
          "name" => error.message,
          "exception" => error,
          "response" => error.response }}, options)
      end

      def resource_id(resource)
        if resource.is_a? Hash
          resource["id"]
        elsif resource.is_a? Response
          resource.params["id"]
        else
          resource
        end
      end

      def build_http_header(options)
        header = {}
        header.merge!( "PayPal-Request-Id" => options[:request_id] ) if options[:request_id]
        header.merge!(options[:header]) if options[:header].is_a? Hash
        header
      end

      def build_response(data, options)
        if data.is_a? Hash and data["error"]
          message = data["error"]["name"] || "Failed"
          Response.new(false, message, data["error"], options)
        else
          Response.new(true, "Success", data, options)
        end
      end

      def build_payment(intent, money, options)
        payment = {
          :intent => intent,
          :payer  => build_payer(options),
          :transactions => [ build_transaction(money, options) ] }
        redirect_urls = build_redirect_urls(options)
        payment[:redirect_urls] = redirect_urls if redirect_urls.any?
        payment
      end

      def build_redirect_urls(options)
        options[:cancel_url] = options[:cancel_return_url] if options[:cancel_return_url]
        redirect_urls = {}
        [ :cancel_url, :return_url ].each do |key|
          redirect_urls[key] = options[key] if options[key]
        end
        redirect_urls
      end

      def build_transaction(money, options)
        transaction = {}
        transaction[:amount] = build_amount(money, options)
        transaction[:description] = options[:description] if options[:description]

        item_list = build_item_list(options)
        transaction[:item_list] = item_list if item_list.any?

        transaction
      end

      def build_item_list(options)
        item_list = {}
        items = build_items(options)
        item_list[:items] = items if items
        if options[:shipping_address]
          item_list[:shipping_address] = build_shipping_address(options[:shipping_address], options)
        end
        item_list
      end

      def build_items(options)
        currency_code = options[:currency] || default_currency

        options[:items].map do |item|
          item = item.dup
          item[:price] = item.delete(:amount) if item.has_key? :amount
          requires!(item, :name, :price, :quantity)

          item[:currency] ||= options[:currency] || currency(item[:price])
          item[:price] = localized_amount(item[:price], item[:currency])
          item
        end if options[:items]
      end

      AddressFields = { :line1 => :address1, :line2 => :address2,
        :country_code => :country, :postal_code => :zip }

      def build_address(address, options)
        address = address.dup
        AddressFields.each do |new_key, key|
          address[new_key] = address.delete(key) if address.has_key? key
        end
        requires!(address, :line1, :city, :country_code, :state)
        address
      end

      def build_shipping_address(address, options)
        address = build_address(address, options)
        address[:recipient_name] = address.delete(:name) if address.has_key? :name
        requires!(address, :recipient_name)
        address
      end

      AmountDetails = [ :tax, :shipping, :subtotal, :fee ]

      def build_amount(money, options)
        currency_code = options[:currency] || currency(money)
        amount = {
          :total => localized_amount(money, currency_code),
          :currency => currency_code }

        details = {}
        AmountDetails.each do |value|
          details[value] = localized_amount(options[value], currency_code) if options[value]
        end
        amount[:details] = details if details.any?

        amount
      end

      def build_payer(options)
        if options[:credit_card]
          {
            :payment_method => "credit_card",
            :funding_instruments => [ build_funding_instrument(options) ] }
        else
          requires!(options, :return_url, :cancel_url)
          { :payment_method => "paypal" }
        end
      end

      def build_funding_instrument(options)
        if options[:credit_card].is_a? CreditCard
          { :credit_card => build_credit_card(options[:credit_card], options) }
        else
          { :credit_card_token => { :credit_card_id => options[:credit_card].to_s } }
        end
      end

      def build_credit_card(credit_card, options)
        credit_card = {
          :type => card_brand(credit_card),
          :number => credit_card.number,
          :expire_month => format(credit_card.month, :two_digits),
          :expire_year  => format(credit_card.year,  :four_digits),
          :cvv2 => credit_card.verification_value,
          :first_name => credit_card.first_name,
          :last_name => credit_card.last_name }
        address = options[:billing_address] || options[:address]
        credit_card[:billing_address] = build_address(address, options) if address
        credit_card
      end

    end
  end
end
