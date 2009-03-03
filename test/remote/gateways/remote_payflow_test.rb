require File.dirname(__FILE__) + '/../../test_helper'
require 'pp'

class RemotePayflowTest < Test::Unit::TestCase
  def setup
    ActiveMerchant::Billing::Base.gateway_mode = :test

    @gateway = PayflowGateway.new(fixtures(:payflow))
    
    @credit_card = credit_card('5105105105105100', :type => 'master')

    @options = { 
      :billing_address => address,
      :email => 'cody@example.com',
      :customer => 'codyexample'
    }

    @options = { 
      :billing_address => {
        :name     => 'John Doe',
        :address1 => '123 Street Rd', 
        :city     => 'Somewhere',
        :state    => 'MD',
        :zip      => '20879',
        :country  => 'US',
        :phone    => '(555)123-4567'
      },
      # description is needed to make Payflow's test server behave appropriately
      # for ACH transactions, according to a Paypal support tech: 
      #   "I spoke to a couple of our engineers, and the test server sometimes has 
      #    problems with the ACH when testing. ...you shouldn't have to worry about 
      #    this error on the test server. ...to get your code to go through on the 
      #    test server, [pass] a description with your XML request."
      # ** Note: This is handled in the class itself **
      # :description => 'Widget'
    }

    # Do this because if you use the same account number over and over
    # the Payflow gateway will complain, mainly when voiding
    @check = check(:account_number => Time.now.strftime('%Y%m%d%H%I%S'))

  end

  def test_successful_purchase_for_credit_card
    assert response = @gateway.purchase(100000, @credit_card, @options)
    assert_approved response
    assert_success response
    assert response.test?
    assert_not_nil response.authorization
  end
  
  def test_successful_purchase_for_check
    assert response = @gateway.purchase(100000, @check, @options)
    assert_approved response
    assert_success response
    assert response.test?
    assert_not_nil response.authorization
  end
    
  def test_declined_purchase_for_credit_card
    assert response = @gateway.purchase(2100000, @credit_card, @options)
    assert_equal 'Declined', response.message
    assert_failure response
    assert response.test?
  end
  
  def test_declined_purchase_for_check
    assert response = @gateway.purchase(2100000, @check, @options)
    assert_equal 'Failed merchant rule check', response.message
    assert_failure response
    assert response.test?
  end
  
  def test_successful_authorization_for_credit_card
    assert response = @gateway.authorize(100, @credit_card, @options)
    assert_approved response
    assert_success response
    assert response.test?
    assert_not_nil response.authorization
  end
  
  def test_authorization_for_check_raises_exception
    assert_raise ActiveMerchant::ActiveMerchantError do
      @gateway.authorize(100, @check, @options)
    end
  end
   
  def test_authorize_and_capture
    assert auth = @gateway.authorize(100, @credit_card, @options)
    assert_success auth
    assert_approved auth
    assert auth.authorization
    assert capture = @gateway.capture(100, auth.authorization)
    assert_success capture
  end
  
  def test_authorize_and_partial_capture
    assert auth = @gateway.authorize(100 * 2, @credit_card, @options)
    assert_success auth
    assert_approved auth
    assert auth.authorization
    
    assert capture = @gateway.capture(100, auth.authorization)
    assert_success capture
  end
  
  def test_failed_capture
    assert response = @gateway.capture(100, '999')
    assert_failure response
    assert_equal 'Invalid tender', response.message
  end
  
  def test_authorize_and_void
    assert auth = @gateway.authorize(100, @credit_card, @options)
    assert_success auth
    assert_approved auth
    assert auth.authorization
    
    assert void = @gateway.void(auth.authorization)
    assert_success void
  end
  
  def test_invalid_login
    gateway = PayflowGateway.new(
      :login => '',
      :password => ''
    )
    assert response = gateway.purchase(100, @credit_card, @options)
    assert_equal 'Invalid vendor account', response.message
    assert_failure response
  end
  
  def test_duplicate_request_id_for_credit_card
    request_id = Digest::MD5.hexdigest(rand.to_s)
    ActiveMerchant::Utils.expects(:generate_unique_id).times(2).returns(request_id)
    
    response1 = @gateway.purchase(100, @credit_card, @options)
    assert  response1.success?
    assert_nil response1.params['duplicate']
    
    response2 = @gateway.purchase(100, @credit_card, @options)
    assert response2.success?
    assert response2.params['duplicate']
  end
  
  def test_duplicate_request_id_for_check
    request_id = Digest::MD5.hexdigest(rand.to_s)
    ActiveMerchant::Utils.expects(:generate_unique_id).times(2).returns(request_id)
    
    response1 = @gateway.purchase(100, @check, @options)
    assert  response1.success?
    assert_nil response1.params['duplicate']
    
    response2 = @gateway.purchase(100, @check, @options)
    assert response2.success?
    assert response2.params['duplicate']
  end
  
  # Note that recurring billing will only work if your account handles it,
  # the test should not fail if it doesn't
  def test_create_recurring_profile
    response = @gateway.recurring(1000, @credit_card, :periodicity => :monthly)
    
    return if user_authentication_failed?(response)
    
    assert_success response
    assert !response.params['profile_id'].blank?
    assert response.test?
  end
  
  # Note that recurring billing will only work if your account handles it,
  # the test should not fail if it doesn't
  def test_create_recurring_profile_with_invalid_date
    response = @gateway.recurring(1000, @credit_card, :periodicity => :monthly, :starting_at => Time.now)
    
    return if user_authentication_failed?(response)
    
    assert_failure response
    assert_equal 'Field format error: Start or next payment date must be a valid future date', response.message
    assert response.params['profile_id'].blank?
    assert response.test?
  end
  
  # Note that recurring billing will only work if your account handles it,
  # the test should not fail if it doesn't
  def test_create_and_cancel_recurring_profile
    response = @gateway.recurring(1000, @credit_card, :periodicity => :monthly)
    
    return if user_authentication_failed?(response)
    
    assert_success response
    assert !response.params['profile_id'].blank?
    assert response.test?
    
    response = @gateway.cancel_recurring(response.params['profile_id'])
    assert_success response
    assert response.test?
  end
  
  # Note that recurring billing will only work if your account handles it,
  # the test should not fail if it doesn't
  def test_recurring_with_initial_authorization
    response = @gateway.recurring(1000, @credit_card, 
      :periodicity => :monthly,
      :initial_transaction => {
        :type => :authorization
      }
    )
    return if user_authentication_failed?(response)
    
    assert_success response
    assert !response.params['profile_id'].blank?
    assert response.test?
  end
  
  # Note that recurring billing will only work if your account handles it,
  # the test should not fail if it doesn't
  def test_recurring_with_initial_authorization
    response = @gateway.recurring(1000, @credit_card, 
      :periodicity => :monthly,
      :initial_transaction => {
        :type => :purchase,
        :amount => 500
      }
    )
  
    return if user_authentication_failed?(response)
    
    assert_success response
    assert !response.params['profile_id'].blank?
    assert response.test?
  end
  
  # Note that recurring billing will only work if your account handles it,
  # the test should not fail if it doesn't
  def test_full_feature_set_for_recurring_profiles
    # Test add
    @options.update(
      :periodicity => :weekly,
      :payments => '12',
      :starting_at => Time.now + 1.day,
      :comment => "Test Profile"
    )
    response = @gateway.recurring(100, @credit_card, @options)
    
    return if user_authentication_failed?(response)
  
    assert_equal "Approved", response.params['message']
    assert_equal "0", response.params['result']
    assert_success response
    assert response.test?
    assert !response.params['profile_id'].blank?
    @recurring_profile_id = response.params['profile_id']
  
    # Test modify
    @options.update(
      :periodicity => :monthly,
      :starting_at => Time.now + 1.day,
      :payments => '4',
      :profile_id => @recurring_profile_id
    )
    response = @gateway.recurring(400, @credit_card, @options)
    assert_equal "Approved", response.params['message']
    assert_equal "0", response.params['result']
    assert_success response
    assert response.test?
    
    # Test inquiry
    response = @gateway.recurring_inquiry(@recurring_profile_id) 
    assert_equal "0", response.params['result']
    assert_success response
    assert response.test?
    
    # Test payment history inquiry
    response = @gateway.recurring_inquiry(@recurring_profile_id, :history => true)
    assert_equal '0', response.params['result']
    assert_success response
    assert response.test?
    
    # Test cancel
    response = @gateway.cancel_recurring(@recurring_profile_id)
    assert_equal "Approved", response.params['message']
    assert_equal "0", response.params['result']
    assert_success response
    assert response.test?
  end
  
  # Note that this test will only work if you enable reference transactions!!
  def test_reference_purchase
    assert response = @gateway.purchase(10000, @credit_card, @options)
    assert_approved response
    assert_success response
    assert response.test?
    assert_not_nil pn_ref = response.authorization
    
    # now another purchase, by reference
    assert response = @gateway.purchase(10000, pn_ref)
    assert_approved response
    assert_success response
    assert response.test?
  end
  
  def test_purchase_and_referenced_credit
    amount = 100
    
    assert purchase = @gateway.purchase(amount, @credit_card, @options)
    assert_success purchase
    assert_approved purchase
    assert !purchase.authorization.blank?
    
    assert credit = @gateway.credit(amount, purchase.authorization)
    assert_success credit
  end
  
  # This test randomly passes/fails, depending on the test server's mood
  def test_purchase_and_void_for_check
    assert purchase = @gateway.purchase(1000, @check, @options)
    assert_success purchase
    assert_approved purchase
    
    assert void = @gateway.void(purchase.authorization, @options)
    assert_success void
    assert_approved void
  end
  
  # This test randomly passes/fails, depending on the test server's mood
  def test_purchase_and_credit_for_check
    assert purchase = @gateway.purchase(1000, @check, @options)
    assert_success purchase
    assert_approved purchase
    
    assert void = @gateway.credit(1000, purchase.authorization, @options)
    assert_success void
    assert_approved void
  end

  # This test should pass, but because the Payflow test server doesn't
  # produce the correct response (and the response varies too), it won't
  def test_purchase_and_credit_for_check_with_differing_amounts
    assert purchase = @gateway.purchase(10000, @check, @options)
    assert_success purchase
    assert_approved purchase
    
    assert void = @gateway.credit(500, purchase.authorization, @options)
    assert_success void
    assert_not_equal 'Approved', void.message
  end


  # The default security setting for Payflow Pro accounts is Allow 
  # non-referenced credits = No.
  #
  # Non-referenced credits will fail with Result code 117 (failed the security 
  # check) unless Allow non-referenced credits = Yes in PayPal manager
  def test_purchase_and_non_referenced_credit
    assert credit = @gateway.credit(100, @credit_card, @options)
    assert_success credit
  end
  
  private
  def user_authentication_failed?(response)
    response.message == 'User authentication failed: Recurring Billing'
  end
  
  def assert_approved(response)
    assert_equal('Approved', response.message)
  end
end
