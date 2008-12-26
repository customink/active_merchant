require File.dirname(__FILE__) + '/../../test_helper'

class SecureNetTest < Test::Unit::TestCase
  def setup
    @gateway = SecureNetGateway.new(
      :login => 'login',
      :password => 'password',
      :test => 'test'
    )

    @credit_card = credit_card
    @amount = 100
    
    @options = { 
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end
  
  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response
    
    # Replace with authorization number from the successful response
    assert_equal '123456', response.authorization
    assert response.test?
  end

  def test_unsuccessful_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert response.test?
  end

  private
  
  # Place raw successful response from gateway here
  def successful_purchase_response
    SUCCESS
  end
  
  # Place raw failed response from gateway here
  def failed_purchase_response
    FAIL
  end

  SUCCESS = <<EOSUCCESS
<?xml version="1.0" encoding="utf-8"?>
<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
  <soap12:Body>
    <ProcessResponse xmlns="https://gateway.securenet.com/">
      <ProcessResult>
        <FirstName>Happy</FirstName>
        <LastName>Gilmore</LastName>
        <Response_Code>1</Response_Code>
        <Response_Reason_Text>Because, why not?</Response_Reason_Text>
        <Approval_Code>123456</Approval_Code>
        <AVS_Result_Code>M</AVS_Result_Code>
        <Card_Code_Response_Code>M</Card_Code_Response_Code>
        <CAVV_Response_Code>2</CAVV_Response_Code>
      </ProcessResult>
    </ProcessResponse>
  </soap12:Body>
</soap12:Envelope>
EOSUCCESS

FAIL = <<EOFAIL
<?xml version="1.0" encoding="utf-8"?>
<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
  <soap12:Body>
    <ProcessResponse xmlns="https://gateway.securenet.com/">
      <ProcessResult>
        <FirstName>Happy</FirstName>
        <LastName>Gilmore</LastName>
        <Response_Code>2</Response_Code>
        <Response_Reason_Text>I don't hear you laughin' now!</Response_Reason_Text>
        <Approval_Code>123456</Approval_Code>
        <AVS_Result_Code>M</AVS_Result_Code>
        <Card_Code_Response_Code>M</Card_Code_Response_Code>
        <CAVV_Response_Code>2</CAVV_Response_Code>
      </ProcessResult>
    </ProcessResponse>
  </soap12:Body>
</soap12:Envelope>
EOFAIL
end
