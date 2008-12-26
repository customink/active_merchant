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
        @address = options[:billing_address] || options[:address]
        requires!(options, :order_id)
        post = {}
        add_invoice(post, options)
        add_creditcard(post, creditcard)        
        add_address(post, creditcard, options)        
        add_customer_data(post, options)
        
        commit('authonly', money, post)
      end

      # Requires :order_id in the options hash.
      def purchase(money, creditcard, options = {})
        requires!(options, :order_id)
        @address = options[:billing_address] || options[:address]
        xml_request(options) do |xml|
          @xml = xml
          xml.Type('AUTH_CAPTURE')
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
        commit('capture', money, post)
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
                xml.OrderID(options[:order_id])
                xml.Method('CC')
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
        puts data
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