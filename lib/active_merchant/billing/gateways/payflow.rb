require File.dirname(__FILE__) + '/payflow/payflow_common_api'
require File.dirname(__FILE__) + '/payflow/payflow_response'
require File.dirname(__FILE__) + '/payflow_express'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayflowGateway < Gateway
      include PayflowCommonAPI
      
      RECURRING_ACTIONS = Set.new([:add, :modify, :cancel, :inquiry, :reactivate, :payment])
       
      self.supported_cardtypes = [:visa, :master, :american_express, :jcb, :discover, :diners_club]
      self.homepage_url = 'https://www.paypal.com/cgi-bin/webscr?cmd=_payflow-pro-overview-outside'
      self.display_name = 'PayPal Payflow Pro'

      def inquiry(authorization, options = {})
        xml = Builder::XmlMarkup.new
        xml.GetStatus do
          xml.PNRef authorization
        end

        commit( xml.target! )
      end

      # Note: Payflow does not support this for ACH transactions
      def authorize(money, cc_or_ref, options = {})
        raise ActiveMerchantError, 'Illegal action: cannot perform an authorization for ACH' if cc_or_ref.class.to_s =~ /Check$/
        request = build_sale_or_authorization_request(:authorization, money, cc_or_ref, options)
      
        commit(request)
      end
      
      def purchase(money, cc_or_ref_or_check, options = {})
        request = build_sale_or_authorization_request(:purchase, money, cc_or_ref_or_check, options)

        commit(request)
      end
      
      def credit(money, cc_or_ref_or_check, options = {})
        if cc_or_ref_or_check.is_a?(String)
          # Perform referenced credit
          request = build_reference_request(:credit, money, cc_or_ref_or_check, options)
        else
          # Perform non-referenced credit
          request = build_credit_card_or_check_request(:credit, money, cc_or_ref_or_check, options)
        end
        
        commit(request)
      end
      
      # Adds or modifies a recurring Payflow profile.  See the Payflow Pro Recurring Billing Guide for more details:
      # https://www.paypal.com/en_US/pdf/PayflowPro_RecurringBilling_Guide.pdf
      #    
      # Several options are available to customize the recurring profile:
      #
      # * <tt>profile_id</tt> - is only required for editing a recurring profile
      # * <tt>starting_at</tt> - takes a Date, Time, or string in mmddyyyy format. The date must be in the future.
      # * <tt>name</tt> - The name of the customer to be billed.  If not specified, the name from the credit card is used.
      # * <tt>periodicity</tt> - The frequency that the recurring payments will occur at.  Can be one of
      # :bimonthly, :monthly, :biweekly, :weekly, :yearly, :daily, :semimonthly, :quadweekly, :quarterly, :semiyearly
      # * <tt>payments</tt> - The term, or number of payments that will be made
      # * <tt>comment</tt> - A comment associated with the profile            
      def recurring(money, credit_card, options = {})
        options[:name] = credit_card.name if options[:name].blank? && credit_card
        request = build_recurring_request(options[:profile_id] ? :modify : :add, money, options) do |xml|
          add_credit_card(xml, credit_card) if credit_card
        end
        commit(request, :recurring)
      end
      
      def cancel_recurring(profile_id)
        request = build_recurring_request(:cancel, 0, :profile_id => profile_id)
        commit(request, :recurring)
      end
      
      def recurring_inquiry(profile_id, options = {})
        request = build_recurring_request(:inquiry, nil, options.update( :profile_id => profile_id ))
        commit(request, :recurring)
      end   
      
      def express
        @express ||= PayflowExpressGateway.new(@options)
      end
      
      private
      def build_sale_or_authorization_request(action, money, cc_or_ref_or_check, options)
        if cc_or_ref_or_check.is_a?(String) # String => reference
          build_reference_sale_or_authorization_request(action, money, cc_or_ref_or_check, options)
        else  
          build_credit_card_or_check_request(action, money, cc_or_ref_or_check, options)
        end  
      end
      
      def build_reference_sale_or_authorization_request(action, money, reference, options)
        xml = Builder::XmlMarkup.new 
        xml.tag! TRANSACTIONS[action] do
          xml.tag! 'PayData' do
            xml.tag! 'Invoice' do
              xml.tag! 'TotalAmt', amount(money), 'Currency' => options[:currency] || currency(money)
            end
            xml.tag! 'Tender' do
              xml.tag! 'Card' do
                xml.tag! 'ExtData', 'Name' => 'ORIGID', 'Value' =>  reference
              end
            end
          end
        end
        xml.target!
      end
      
      def build_credit_card_or_check_request(action, money, credit_card_or_check, options)
        options[:description] = 'Test' if test? && options[:description].blank?

        xml = Builder::XmlMarkup.new
        xml.tag! TRANSACTIONS[action] do
          xml.tag! 'PayData' do
            xml.tag! 'Invoice' do
              xml.tag! 'CustIP', options[:ip] unless options[:ip].blank?
              xml.tag! 'InvNum', options[:order_id].to_s.gsub(/[^\w.]/, '') unless options[:order_id].blank?
              xml.tag! 'Description', options[:description] unless options[:description].blank?

              billing_address = options[:billing_address] || options[:address]
              add_address(xml, 'BillTo', billing_address, options) if billing_address
              add_address(xml, 'ShipTo', options[:shipping_address], options) if options[:shipping_address]
              
              xml.tag! 'TotalAmt', amount(money), 'Currency' => options[:currency] || currency(money)
            end

            add_tender(xml, credit_card_or_check)
          end 
        end
        xml.target!
      end

      def add_tender(xml, tender)
        xml.tag! 'Tender' do
          case tender.class.to_s
          when /CreditCard$/ then add_credit_card(xml, tender)
          when /Check$/      then add_check(xml, tender)
          end
        end
      end
    
      def add_check(xml, check)
        xml.tag! 'ACH' do
          xml.tag! 'AcctType', check.account_type[0..0].upcase
          xml.tag! 'AcctNum',  check.account_number
          xml.tag! 'ABA',      check.routing_number
          xml.tag! 'AuthType', 'WEB'
        end
      end
    
      def add_credit_card(xml, credit_card)
        xml.tag! 'Card' do
          xml.tag! 'CardType', credit_card_type(credit_card)
          xml.tag! 'CardNum', credit_card.number
          xml.tag! 'ExpDate', expdate(credit_card)
          xml.tag! 'NameOnCard', credit_card.first_name
          xml.tag! 'CVNum', credit_card.verification_value if credit_card.verification_value?
          
          if requires_start_date_or_issue_number?(credit_card)
            xml.tag!('ExtData', 'Name' => 'CardStart', 'Value' => startdate(credit_card)) unless credit_card.start_month.blank? || credit_card.start_year.blank?
            xml.tag!('ExtData', 'Name' => 'CardIssue', 'Value' => format(credit_card.issue_number, :two_digits)) unless credit_card.issue_number.blank?
          end
          xml.tag! 'ExtData', 'Name' => 'LASTNAME', 'Value' =>  credit_card.last_name
        end
      end
      
      def credit_card_type(credit_card)
        return '' if card_brand(credit_card).blank?
        
        CARD_MAPPING[card_brand(credit_card).to_sym]
      end
      
      def expdate(creditcard)
        year  = sprintf("%.4i", creditcard.year)
        month = sprintf("%.2i", creditcard.month)

        "#{year}#{month}"
      end
      
      def startdate(creditcard)
        year  = format(creditcard.start_year, :two_digits)
        month = format(creditcard.start_month, :two_digits)

        "#{month}#{year}"
      end
      
      def build_recurring_request(action, money, options)
        unless RECURRING_ACTIONS.include?(action)
          raise StandardError, "Invalid Recurring Profile Action: #{action}"
        end

        xml = Builder::XmlMarkup.new 
        xml.tag! 'RecurringProfiles' do
          xml.tag! 'RecurringProfile' do
            xml.tag! action.to_s.capitalize do
              unless [:cancel, :inquiry].include?(action)
                xml.tag! 'RPData' do
                  xml.tag! 'Name', options[:name] unless options[:name].nil?
                  xml.tag! 'TotalAmt', amount(money), 'Currency' => options[:currency] || currency(money)
                  xml.tag! 'PayPeriod', get_pay_period(options)
                  xml.tag! 'Term', options[:payments] unless options[:payments].nil?
                  xml.tag! 'Comment', options[:comment] unless options[:comment].nil?
                
                
                  if initial_tx = options[:initial_transaction]
                    requires!(initial_tx, [:type, :authorization, :purchase])
                    requires!(initial_tx, :amount) if initial_tx[:type] == :purchase
                      
                    xml.tag! 'OptionalTrans', TRANSACTIONS[initial_tx[:type]]
                    xml.tag! 'OptionalTransAmt', amount(initial_tx[:amount]) unless initial_tx[:amount].blank?
                  end
                
                  xml.tag! 'Start', format_rp_date(options[:starting_at] || Date.today + 1 )
                  xml.tag! 'EMail', options[:email] unless options[:email].nil?
                  
                  billing_address = options[:billing_address] || options[:address]
                  add_address(xml, 'BillTo', billing_address, options) if billing_address
                  add_address(xml, 'ShipTo', options[:shipping_address], options) if options[:shipping_address]
                end
                xml.tag! 'Tender' do
                  yield xml
                end
              end
              if action != :add
                xml.tag! "ProfileID", options[:profile_id]
              end
              if action == :inquiry
                xml.tag! "PaymentHistory", ( options[:history] ? 'Y' : 'N' )
              end
            end
          end
        end
      end

      def get_pay_period(options)
        requires!(options, [:periodicity, :bimonthly, :monthly, :biweekly, :weekly, :yearly, :daily, :semimonthly, :quadweekly, :quarterly, :semiyearly])
        case options[:periodicity]
          when :weekly then 'Weekly'
          when :biweekly then 'Bi-weekly'
          when :semimonthly then 'Semi-monthly'
          when :quadweekly then 'Every four weeks'
          when :monthly then 'Monthly'
          when :quarterly then 'Quarterly'
          when :semiyearly then 'Semi-yearly'
          when :yearly then 'Yearly'
        end
      end

      def format_rp_date(time)
        case time
          when Time, Date then time.strftime("%m%d%Y")
        else
          time.to_s
        end
      end
      
      def build_response(success, message, response, options = {}) 
        PayflowResponse.new(success, message, response, options)
      end
    end
  end
end

