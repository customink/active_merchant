module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class SecureNetGateway < Gateway
      TEST_URL = 'https://certify.securenet.com/payment.asmx'
      LIVE_URL = 'https://gateway.securenet.com/payment.asmx'
      
      TEST_SH_URL = 'https://certify.securenet.com/sh/SecureHost.asmx'
      LIVE_SH_URL = 'https://gateway.securenet.com/sh/SecureHost.asmx'
      
      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['US']
      
      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      
      # The homepage URL of the gateway
      self.homepage_url = 'http://www.securenet.com/'
      
      # The name of the gateway
      self.display_name = 'SecureNet'

      TaxNotIncluded, TaxIncluded, TaxExempt = 0, 1, 2

      # Requires :login => 'your SecurenetID' and :password => 'your SecureKey'
      # Optionally, pass :test => true to run all operations in test mode.
      def initialize(options = {})
        requires!(options, :login, :password)
        @options = options
        @login, @password = options.values_at( :login, :password )
        super
      end  

      # Requires :order_id in the options hash.
      def authorize(money, creditcard, options = {})
        raise ActiveMerchantError if creditcard.is_a? ActiveMerchant::Billing::Check
        auth_or_purchase('AUTH_ONLY', money, creditcard, options)
      end
      
      def purchase(money, creditcard_or_check, transaction_id = nil, options = {})
        options = transaction_id if transaction_id.is_a? Hash
        auth_or_purchase('AUTH_CAPTURE', money, creditcard_or_check, transaction_id, options)
      end
            
      def auth_or_purchase(type, money, creditcard_or_check, transaction_id = nil, options = {})
        options, transaction_id = [transaction_id, nil] if transaction_id.is_a? Hash
        xml_request(options) do |xml|
          xml.Type(type)
          xml.Amount(amount(money))
          xml.Trans_id(transaction_id) unless transaction_id.nil?
          add_tender(xml, creditcard_or_check) if creditcard_or_check
        end
      end

      def capture(money, transaction_id, creditcard, options = {})
        xml_request(options) do |xml|
          xml.Type('PRIOR_AUTH_CAPTURE')
          xml.Amount(amount(money)) unless money.nil?
          xml.Trans_id(transaction_id)
          add_tender(xml, creditcard) if creditcard
        end
      end

      def credit(money, transaction_id, creditcard_or_check, options = {})
        xml_request(options) do |xml|
          xml.Type('CREDIT')
          xml.Amount(amount(money))
          add_tender(xml, creditcard_or_check) if creditcard_or_check
          xml.Trans_id(transaction_id)
        end
      end

      def void(money, transaction_id, creditcard_or_check, options = {})
        xml_request(options) do |xml|
          xml.Type('VOID')
          xml.Amount(amount(money))
          add_tender(xml, creditcard_or_check) if creditcard_or_check
          xml.Trans_id(transaction_id)
        end
      end

      def credit_or_void(type, money, transaction_id, options = {})
        xml_request(options) do |xml|
          xml.Type(type)
          xml.Amount(amount(money))
          xml.Trans_id(transaction_id)
        end
      end
      
      def store( creditcard_or_check, options = {} )
        options.merge!( :new_customer => true ) { |key, oldval, newval| oldval.nil? ? newval : oldval }
        action = options[:new_customer] ? 'AddCustomerAndAccount' : 'AddAccount'
        
        xml = base_xml do |xml|
          xml.tag!( action, 'xmlns' => 'https://gateway.securenet.com/sh/' ) do
            xml.SecurenetID  @login
            xml.SecureKey    @password
            add_customer( xml, options ) if options[:new_customer]
            add_account( xml, creditcard_or_check, options )
          end
        end

        commit( xml.target!, action )
      end
      
      def unstore( customer_id )
        xml = base_xml do |xml|
          xml.tag!( 'DeleteCustomer', 'xmlns' => 'https://gateway.securenet.com/sh/' ) do
            xml.SecurenetID  @login
            xml.SecureKey    @password
            xml.CustomerID   customer_id
          end
        end
        
        commit( xml.target!, 'DeleteCustomer' )
      end
      
      private

      def xml_request( options = {} )
        action    = 'Process'
        namespace = 'https://gateway.securenet.com/'
        if options[:customer_id] && options[:account_id]
          action << 'TransbyCID'
          namespace << 'sh/'
        end

        xml = base_xml do |xml|
          xml.tag!( action, 'xmlns' => namespace ) do
            if action == 'ProcessTransbyCID'
              xml.SecurenetID        @login
              xml.SecureKey          @password
              xml.CustomerID         options[:customer_id]
              xml.PaymentID          options[:account_id]
              xml.UseTranUserDefined 'false'
            end
            xml.oTi do
              xml.Test         'FALSE' # This is hard-coded as FALSE for a reason, don't change it even for testing
              xml.OrderID      options[:order_id] || ActiveMerchant::Utils.generate_unique_id
              if action == 'Process'
                xml.SecurenetID  @login
                xml.SecureKey    @password
                add_address( xml, options )
                # SecureNet does not support Level2 data at this time for stored account transactions
                # That is why it is only added for 'Process' actions (they don't use stored accounts)
                add_level2( xml, options )
              end
              yield( xml )
            end
          end
        end
        
        commit( xml.target!, action )
      end

      def add_tender( xml, creditcard_or_check )
        if creditcard_or_check.type == 'check'
          check = creditcard_or_check
          raise ActiveMerchantError, 'SecureNet requires a bank name for ACH transactions' if check.bank_name.blank?
          xml.Method         'ECHECK' 
          xml.Bank_acct_name check.name 
          xml.Bank_acct_num  check.account_number 
          xml.Bank_aba_code  check.routing_number 
          xml.Bank_acct_type check.account_type.upcase 
          xml.Bank_name      check.bank_name 
        else
          cc = creditcard_or_check
          xml.Method     'CC' 
          xml.Card_num   cc.number
          xml.Exp_date   expdate( cc ) unless cc.year.nil? || cc.month.nil?
          xml.Card_code  cc.verification_value unless cc.verification_value.blank?
        end
      end

      def add_customer( xml, options )
        xml.oCi do
          xml.SecurenetID @login
          add_customer_info( xml, options )
        end
      end

      def add_account( xml, creditcard_or_check, options )
        xml.oAi do
          xml.Securenet_id       @login
          xml.Payment_id         options[:account_id]
          xml.Primary            options[:primary]
          add_customer_info( xml, options )
          
          if creditcard_or_check.type == 'check'
            check = creditcard_or_check
            # raise ActiveMerchantError, 'SecureNet requires a bank name for ACH transactions' if check.bank_name.blank?
            xml.Method 'ECHECK' 
            xml.Bank_ACCNT_name check.name 
            xml.Bank_ACCNT_num  check.account_number 
            xml.Bank_ABA_code   check.routing_number 
            xml.Bank_ACCNT_type check.account_type.upcase 
            xml.Bank_name       check.bank_name
          else
            cc = creditcard_or_check
            xml.Method   'CC'
            xml.Card_num  cc.number 
            xml.Exp_date  expdate( cc ) unless cc.year.nil? || cc.month.nil?
            xml.Card_code cc.verification_value unless cc.verification_value.blank?
            # xml.CardType           options[:card_type]
            # xml.Acctlast4          options[:]
          end
        end
      end
      
      def add_customer_info( xml, options )
        xml.Customer_id  options[:customer_id]
        xml.First_Name   options[:first_name]
        xml.Last_Name    options[:last_name]
        add_address( xml, options )
        xml.Email        options[:email]
        xml.EmailReceipt options[:email_receipt]
        xml.Notes        options[:notes]
      end

      def add_address( xml, options )
        if address = address_from( options )
          xml.Address address[:address1]
          xml.City    address[:city]
          xml.State   address[:state]
          xml.Zip     address[:zip]
          xml.Country address[:country]
          xml.Phone   address[:phone]
        end
      end

      def add_level2( xml, options )
        xml.Level2_Tax      options[:tax_amount]
        xml.Level2_TaxFlag  options[:tax_status]
        xml.Level2_Freight  options[:freight]
        xml.Level2_Duty     options[:duty]   
        xml.Level2_PONumber options[:po_number]
      end

      def base_xml
        xml = Builder::XmlMarkup.new( :indent => 2 )
        xml.instruct!
        xml.tag!( 'soap12:Envelope', 
          'xmlns:xsi'    => 'http://www.w3.org/2001/XMLSchema-instance',
          'xmlns:xsd'    => 'http://www.w3.org/2001/XMLSchema',
          'xmlns:soap12' => 'http://www.w3.org/2003/05/soap-envelope'
        ) do
          xml.tag!( 'soap12:Body' ) do
            yield( xml )
          end
        end
        xml
      end

      def commit( xml, action = 'Process' )
        # puts xml, ''
        url = if action != 'Process'
          test? ? TEST_SH_URL : LIVE_SH_URL
        else
          test? ? TEST_URL : LIVE_URL
        end
        
        post = ssl_post( url, xml, { 'Content-Length' => xml.length.to_s, 'Content-Type' => 'text/xml' } )
        response = parse( post, action )

        Response.new(response[:response_code] == "1", message_from(response), response,
          :authorization => response[:transaction_id],
          :test => test?,
          :cvv_result => response[:cavv_response_code],
          :avs_result => { :code => response[:avs_result_code] }
        )
      end

      def parse( data, action = 'Process' )
        # puts data, ''
        response = {}
        xml = REXML::Document.new(data)
        root = REXML::XPath.first(xml, "//#{action}Result")

        root.elements.to_a.each do |node|
          response[node.name.underscore.to_sym] = node.text
        end
        response
      end

      def expdate(creditcard)
        year  = sprintf("%.4i", creditcard.year)
        month = sprintf("%.2i", creditcard.month)

        "#{month}#{year[-2..-1]}"
      end
      
      def address_from( options )
        address = options[:billing_address] || options[:address]
        # SecureNet only allows for one line of address, and it can be no longer than
        # 60 characters in length.
        unless address.blank?
          address[:address1] = address.values_at(:address1, :address2).compact.join(", ")[0...60]
          address[:address2] = nil
        end
        address
      end
      
      def message_from(response)
        response[:response_reason_text]
      end
      
      def post_data(action, parameters = {})
      end

      # Is the gateway running in test mode?
      def test?
        @options[:test] || super
      end
      
    end
  end
end