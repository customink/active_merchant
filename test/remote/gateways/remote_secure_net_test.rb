require File.dirname(__FILE__) + '/../../test_helper'

class RemoteSecureNetTest < Test::Unit::TestCase
  

  def setup
    @gateway = SecureNetGateway.new(fixtures(:secure_net))
    
    @amount = 100
    @credit_card = credit_card('4000100011112224')
    @declined_card = credit_card('4000300011112220')
    
    @options = { 
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end
  
  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
  end

  def test_unsuccessful_purchase
    assert response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    # TODO: We want this to be declined. Waiting on SecureNet to tell us how
    # to force that condition.
    assert_equal 'ORDERID PROVIDED MUST BE UNIQUE FOR YOUR ACCOUNT', response.message
  end

  def test_authorize_and_capture
    amount = @amount
    assert auth = @gateway.authorize(amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Success', auth.message
    assert auth.authorization
    assert capture = @gateway.capture(amount, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    assert response = @gateway.capture(@amount, '')
    assert_failure response
    assert_equal 'REPLACE WITH GATEWAY FAILURE MESSAGE', response.message
  end

  def test_invalid_login
    gateway = SecureNetGateway.new(
                :login => '',
                :password => ''
              )
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'SECURENET ID IS REQUIRED', response.message
  end
end
