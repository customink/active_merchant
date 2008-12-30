module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class SecureNetGateway < Gateway
      TEST_URL = 'https://certify.securenet.com/payment.asmx'
      LIVE_URL = 'https://gateway.securenet.com/payment.asmx'
      
      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['US']
      
      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      
      # The homepage URL of the gateway
      self.homepage_url = 'http://www.securenet.com/'
      
      # The name of the gateway
      self.display_name = 'SecureNet'

      # Requires :login => 'your SecurenetID' and :password => 'your SecureKey'
      # Optionally, pass :test => true to run all operations in test mode.
      def initialize(options = {})
        requires!(options, :login, :password)
        @options = options
        super
      end  

      # Requires :order_id in the options hash.
      def authorize(money, creditcard, options = {})                
        auth_or_purchase('AUTH_ONLY', money, creditcard, options)
      end

      def purchase(money, creditcard, options = {})
        # Requires :order_id in the options hash.
        requires!(options, :order_id)
        auth_or_purchase('AUTH_CAPTURE', money, creditcard, options)
      end
            
      def auth_or_purchase(type, money, creditcard, options = {})        
        xml_request(options) do |xml|
          @xml = xml
          xml.Type(type)
          xml.Amount(amount(money))
          xml.First_name(creditcard.first_name)
          xml.Last_name(creditcard.last_name)
          xml.Card_num(creditcard.number)
          xml.Exp_date(expdate(creditcard))
          xml.Card_code(creditcard.verification_value)
        end
        commit(@xml.target!)
      end                       
    
      def capture(money, authorization, options = {})
       # requires!(options, :order_id)
        xml_request(options) do |xml|
          @xml = xml
          xml.Type('CAPTURE_ONLY')
          xml.Amount(amount(money))
          xml.Auth_code(authorization)
#          xml.First_name(creditcard.first_name)
#          xml.Last_name(creditcard.last_name)
#          xml.Card_num(creditcard.number)
#          xml.Exp_date(expdate(creditcard))
#          xml.Card_code(creditcard.verification_value)
        end
        commit(@xml.target!)
      end
    
      private

      def message_from(response)
        response[:response_reason_text]
      end
      
      def post_data(action, parameters = {})
      end

      # Is the gateway running in test mode?
      def test?
        @options[:test] || super
      end

      def xml_request(options = {})
        xml = Builder::XmlMarkup.new
        @address = options[:billing_address] || options[:address]
        # SecureNet only allows for one line of address, and it can be no longer than
        # 60 characters in length.
        unless @address.blank?
          [@address[:address1],@address[:address2]].compact.join(", ")[0...60]
        end
        xml.instruct!
        xml.tag!('soap12:Envelope', 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
          'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema',
          'xmlns:soap12' => 'http://www.w3.org/2003/05/soap-envelope') do
          xml.tag!('soap12:Body') do
            xml.tag!('Process', 'xmlns' => 'https://gateway.securenet.com/') do
              xml.oTi do
                xml.SecurenetID(@options[:login])
                xml.SecureKey(@options[:password])
                xml.Test('TRUE') if test?
                xml.OrderID(options[:order_id]) unless options[:order_id].blank?
                xml.Method('CC')
                unless @address.blank?
                  xml.Address(@address[:address1])
                  xml.City(@address[:city])
                  xml.State(@address[:state])
                  xml.Zip(@address[:zip])
                  xml.Country(@address[:country]) unless @address[:country].blank?
                  xml.Phone(@address[:phone]) unless @address[:phone].blank?
                end
                yield(xml)
              end
            end
          end
        end
        xml
      end

      def commit(xml)

        response = parse( ssl_post(test? ? TEST_URL : LIVE_URL, xml,
            {'Content-Length' => xml.length.to_s,
             'Content-Type' => 'text/xml'}) )

        Response.new(response[:response_code] == "1", message_from(response), response,
          :authorization => response[:approval_code],
          :test => test?,
          :cvv_result => response[:cavv_response_code],
          :avs_result => { :code => response[:avs_result_code] }
        )

      end

      def parse(data)
        response = {}
        xml = REXML::Document.new(data)
        root = REXML::XPath.first(xml, "//ProcessResult")

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
    end
  end
end