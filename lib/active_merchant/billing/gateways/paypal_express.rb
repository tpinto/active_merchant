require File.dirname(__FILE__) + '/paypal/paypal_common_api'
require File.dirname(__FILE__) + '/paypal/paypal_express_response'
require File.dirname(__FILE__) + '/paypal_express_common'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PaypalExpressGateway < Gateway
      include PaypalCommonAPI
      include PaypalExpressCommon
      
      self.test_redirect_url = 'https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token='
      self.supported_countries = ['US']
      self.homepage_url = 'https://www.paypal.com/cgi-bin/webscr?cmd=xpt/merchant/ExpressCheckoutIntro-outside'
      self.display_name = 'PayPal Express Checkout'
      
      # recurring payment:
      #   SetExpressCheckout              setup_agreement
      #   redirect to paypal
      #   back from paypal
      #   GetExpressCheckoutDetails       details_for
      #   CreateRecurringPaymentsProfile  create_profile
      
      # normal payment:
      #   SetExpressCheckout              setup_purchase
      #   redirect to paypal
      #   back from paypal
      #   GetExpressCheckoutDetails       details_for
      #   DoExpressCheckoutPayment        purchase
      
      def setup_authorization(money, options = {})
        requires!(options, :return_url, :cancel_url)
        
        commit 'SetExpressCheckout', build_setup_request('Authorization', money, options)
      end
      
      def authorize(money, options = {})
        requires!(options, :token, :payer_id)
      
        commit 'DoExpressCheckoutPayment', build_sale_or_authorization_request('Authorization', money, options)
      end
      
      def setup_purchase(money, options = {})
        requires!(options, :return_url, :cancel_url)
        
        commit 'SetExpressCheckout', build_setup_request('Sale', money, options)
      end

      def purchase(money, options = {})
        requires!(options, :token, :payer_id)
        
        commit 'DoExpressCheckoutPayment', build_sale_or_authorization_request('Sale', money, options)
      end

      def details_for(token)
        commit 'GetExpressCheckoutDetails', build_get_details_request(token)
      end
      
      def setup_agreement(options = {})
        requires!(options, :description, :return_url, :cancel_url)
      
        commit 'SetExpressCheckout', build_setup_request('Sale', 0, options)
      end
      
      def create_profile(token, options = {})
        requires!(options, :description, :start_date, :frequency, :amount)

        commit 'CreateRecurringPaymentsProfile', build_create_profile_request(token, options)
      end

      def get_profile_details(profile_id)
        commit 'GetRecurringPaymentsProfileDetails', build_get_profile_details_request(profile_id)
      end

      def update_profile(profile_id, options = {})
        commit 'UpdateRecurringPaymentsProfile', build_change_profile_request(profile_id, options)
      end

      def cancel_profile(profile_id, options = {})
        commit 'ManageRecurringPaymentsProfileStatus', build_manage_profile_request(profile_id, 'Cancel', options)
      end

      def suspend_profile(profile_id, options = {})
        commit 'ManageRecurringPaymentsProfileStatus', build_manage_profile_request(profile_id, 'Suspend', options)
      end

      def reactivate_profile(profile_id, options = {})
        commit 'ManageRecurringPaymentsProfileStatus', build_manage_profile_request(profile_id, 'Reactivate', options)
      end

      def bill_outstanding_amount(profile_id, options = {})
        commit 'BillOutstandingAmount', build_bill_outstanding_amount(profile_id, options)
      end

      private
      def build_get_details_request(token)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'GetExpressCheckoutDetailsReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'GetExpressCheckoutDetailsRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'Token', token
          end
        end

        xml.target!
      end
      
      def build_sale_or_authorization_request(action, money, options)
        currency_code = options[:currency] || currency(money)
        
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'DoExpressCheckoutPaymentReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'DoExpressCheckoutPaymentRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:DoExpressCheckoutPaymentRequestDetails' do
              xml.tag! 'n2:PaymentAction', action
              xml.tag! 'n2:Token', options[:token]
              xml.tag! 'n2:PayerID', options[:payer_id]
              xml.tag! 'n2:PaymentDetails' do
                xml.tag! 'n2:OrderTotal', amount(money), 'currencyID' => currency_code
                
                # All of the values must be included together and add up to the order total
                if [:subtotal, :shipping, :handling, :tax].all?{ |o| options.has_key?(o) }
                  xml.tag! 'n2:ItemTotal', amount(options[:subtotal]), 'currencyID' => currency_code
                  xml.tag! 'n2:ShippingTotal', amount(options[:shipping]),'currencyID' => currency_code
                  xml.tag! 'n2:HandlingTotal', amount(options[:handling]),'currencyID' => currency_code
                  xml.tag! 'n2:TaxTotal', amount(options[:tax]), 'currencyID' => currency_code
                end
                
                xml.tag! 'n2:NotifyURL', options[:notify_url]
                xml.tag! 'n2:ButtonSource', application_id.to_s.slice(0,32) unless application_id.blank?
              end
            end
          end
        end

        xml.target!
      end

      def build_setup_request(action, money, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'SetExpressCheckoutReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'SetExpressCheckoutRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:SetExpressCheckoutRequestDetails' do
              # Required fields
              xml.tag! 'n2:ReturnURL', options[:return_url]
              xml.tag! 'n2:CancelURL', options[:cancel_url]
              
              if action == 'Sale' and money == 0
                add_billing_agreement_details(xml, 'n2:BillingAgreementDetails', options[:description])
              else
                add_payment_details(xml, 'n2:PaymentDetails', money, options)
              end
              
              xml.tag! 'n2:AddressOverride', '0'
              
              # Optional fields
              xml.tag! 'n2:NoShipping', options[:no_shipping] ? '1' : '0'
              xml.tag! 'n2:LocaleCode', options[:locale] unless options[:locale].blank?
              
              if options[:allow_guest_checkout]
                xml.tag! 'n2:SolutionType', 'Sole'
                xml.tag! 'n2:LandingPage', 'Billing'
              end
              
              xml.tag! 'n2:ChannelType', 'Merchant'
              xml.tag! 'n2:BrandName', 'Goplan'
              xml.tag! 'n2:GiftMessageEnable', '0'
              xml.tag! 'n2:GiftReceiptEnable', '0'
              xml.tag! 'n2:GiftWrapEnable', '0'

              # Customization of the payment page
              xml.tag! 'n2:PageStyle', options[:page_style] unless options[:page_style].blank?
              xml.tag! 'n2:cpp-image-header', options[:header_image] unless options[:header_image].blank?
              xml.tag! 'n2:cpp-header-back-color', options[:header_background_color] unless options[:header_background_color].blank?
              xml.tag! 'n2:cpp-header-border-color', options[:header_border_color] unless options[:header_border_color].blank?
              xml.tag! 'n2:cpp-payflow-color', options[:background_color] unless options[:background_color].blank?

              xml.tag! 'n2:AddressOverride', options[:address_override] ? '1' : '0'
              add_address(xml, 'n2:Address', options[:shipping_address] || options[:address])
              
              xml.tag! 'n2:IPAddress', options[:ip]
              xml.tag! 'n2:BuyerEmail', options[:email] unless options[:email].blank?
            end
          end
        end

        xml.target!
      end
      
      def build_get_profile_details_request(profile_id)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'GetRecurringPaymentsProfileDetailsReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'GetRecurringPaymentsProfileDetailsRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'ProfileID', profile_id
          end
        end

        xml.target!
      end

      def build_change_profile_request(profile_id, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'UpdateRecurringPaymentsProfileReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'UpdateRecurringPaymentsProfileRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:UpdateRecurringPaymentsProfileRequestDetails' do
              xml.tag! 'ProfileID', profile_id
              xml.tag! 'n2:Note', options[:note] unless options[:note].blank?
              xml.tag! 'n2:Description', options[:description] unless options[:description].blank?
              xml.tag! 'n2:ProfileReference', options[:reference] unless options[:reference].blank?
              xml.tag! 'n2:AdditionalBillingCycles', options[:additional_billing_cycles] unless options[:additional_billing_cycles].blank?
              xml.tag! 'n2:MaxFailedPayments', options[:max_failed_payments] unless options[:max_failed_payments].blank?
              xml.tag! 'n2:AutoBillOutstandingAmount', options[:auto_bill_outstanding] ? 'AddToNextBilling' : 'NoAutoBill'
              if options.has_key?(:amount)
                xml.tag! 'n2:Amount', amount(options[:amount]), 'currencyID' => options[:currency] || 'USD'
              end
              if options.has_key?(:tax_amount)
                xml.tag! 'n2:TaxAmount', amount(options[:tax_amount] || 0), 'currencyID' => options[:currency] || 'USD'
              end
              if options.has_key?(:start_date)
                xml.tag! 'n2:BillingStartDate', (options[:start_date].is_a?(Date) ? options[:start_date].to_time : options[:start_date]).utc.iso8601
              end
            end
          end
        end

        xml.target!
      end
      
      def build_manage_profile_request(profile_id, action, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'ManageRecurringPaymentsProfileStatusReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'ManageRecurringPaymentsProfileStatusRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:ManageRecurringPaymentsProfileStatusRequestDetails' do
              xml.tag! 'ProfileID', profile_id
              xml.tag! 'n2:Action', action
              xml.tag! 'n2:Note', options[:note] unless options[:note].blank?
            end
          end
        end

        xml.target!
      end

      def build_bill_outstanding_amount(profile_id, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'BillOutstandingAmountReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'BillOutstandingAmountRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'ProfileID', profile_id
            if options.has_key?(:amount)
              xml.tag! 'n2:Amount', options[:amount], 'currencyID' => options[:currency] || 'USD'
            end
            xml.tag! 'n2:Note', options[:note] unless options[:note].blank?
          end
        end

        xml.target!
      end
      
      def build_get_profile_details_request(profile_id)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'GetRecurringPaymentsProfileDetailsReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'GetRecurringPaymentsProfileDetailsRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'ProfileID', profile_id
          end
        end

        xml.target!
      end

      def build_change_profile_request(profile_id, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'UpdateRecurringPaymentsProfileReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'UpdateRecurringPaymentsProfileRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:UpdateRecurringPaymentsProfileRequestDetails' do
              xml.tag! 'ProfileID', profile_id
              xml.tag! 'n2:Note', options[:note] unless options[:note].blank?
              xml.tag! 'n2:Description', options[:description] unless options[:description].blank?
              xml.tag! 'n2:ProfileReference', options[:reference] unless options[:reference].blank?
              xml.tag! 'n2:AdditionalBillingCycles', options[:additional_billing_cycles] unless options[:additional_billing_cycles].blank?
              xml.tag! 'n2:MaxFailedPayments', options[:max_failed_payments] unless options[:max_failed_payments].blank?
              xml.tag! 'n2:AutoBillOutstandingAmount', options[:auto_bill_outstanding] ? 'AddToNextBilling' : 'NoAutoBill'
              if options.has_key?(:amount)
                xml.tag! 'n2:Amount', amount(options[:amount]), 'currencyID' => options[:currency] || 'USD'
              end
              if options.has_key?(:tax_amount)
                xml.tag! 'n2:TaxAmount', amount(options[:tax_amount] || 0), 'currencyID' => options[:currency] || 'USD'
              end
              if options.has_key?(:start_date)
                xml.tag! 'n2:BillingStartDate', (options[:start_date].is_a?(Date) ? options[:start_date].to_time : options[:start_date]).utc.iso8601
              end
            end
          end
        end

        xml.target!
      end
      
      def build_manage_profile_request(profile_id, action, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'ManageRecurringPaymentsProfileStatusReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'ManageRecurringPaymentsProfileStatusRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:ManageRecurringPaymentsProfileStatusRequestDetails' do
              xml.tag! 'ProfileID', profile_id
              xml.tag! 'n2:Action', action
              xml.tag! 'n2:Note', options[:note] unless options[:note].blank?
            end
          end
        end

        xml.target!
      end

      def build_bill_outstanding_amount(profile_id, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'BillOutstandingAmountReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'BillOutstandingAmountRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'ProfileID', profile_id
            if options.has_key?(:amount)
              xml.tag! 'n2:Amount', options[:amount], 'currencyID' => options[:currency] || 'USD'
            end
            xml.tag! 'n2:Note', options[:note] unless options[:note].blank?
          end
        end

        xml.target!
      end
      
      def build_response(success, message, response, options = {})
        PaypalExpressResponse.new(success, message, response, options)
      end
    end
  end
end
