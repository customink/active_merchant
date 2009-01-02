require File.dirname(__FILE__) + '/../../test_helper'

class RemoteSecureNetTest < Test::Unit::TestCase
  

  def setup
    @gateway = SecureNetGateway.new(fixtures(:secure_net))
    
    @amount = 1000
    @declined_amount = 20000
    @credit_card = credit_card('4111111111111111', :verification_value => '999')
    order_id = ActiveMerchant::Utils.generate_unique_id
    
    @options = { 
      :order_id => "#{order_id}",
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end
  
  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
  end

  # TODO: We want this to be declined. Waiting on SecureNet to tell us how
    # to force that condition.
  def test_unsuccessful_purchase
    assert response = @gateway.purchase(@declined_amount, @credit_card, @options)
    assert_failure response    
    assert_equal 'Declined  DO NOT HONOR', response.message
  end

  def test_authorize_and_purchase    
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    @options[:order_id] = @options[:order_id].reverse
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
  end

  def test_credit
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert credit = @gateway.credit(@amount, purchase.authorization, :order_id => @options[:order_id].reverse)
    assert_equal 'Success', credit.message
  end

  def test_void
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert void = @gateway.void(@amount, auth.authorization, :order_id => @options[:order_id].reverse)
    assert_equal 'Success', void.message
  end

  # SecureNet allows capture for only card present transactions. Have to use
  # authorize_and_purchase instead.
#  def test_authorize_and_capture
#    amount = @amount
#    assert auth = @gateway.authorize(amount, @credit_card, @options)
#    assert_success auth
#    assert_equal 'Approved', auth.message
#    assert auth.authorization
#    assert capture = @gateway.capture(amount, auth.authorization, @options)
#    assert_success capture
#  end

#  def test_failed_capture
#    assert response = @gateway.capture(@amount, '')
#    assert_failure response
#    assert_equal 'REPLACE WITH GATEWAY FAILURE MESSAGE', response.message
#  end

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
