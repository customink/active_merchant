require File.dirname(__FILE__) + '/../../test_helper'

# TEST DATA
# To run tests in our test environment make sure to set Virtual Terminal to ‘LIVE MODE’, the ‘TEST’ parameter
# as ‘FALSE’, and send the transactions to https://certify.securenet.com/payment.asmx
# To get approved transaction results use these card numbers:
#   370000000000002   American Express
#   601`00000012  Discover
#   5424000000000015  MasterCard
#   4007000000027     Visa
# For AVS Match: 20008
# For CVV/CID Approval: 568
# CVV/CID Visa: 999
# CVV/CID MasterCard: 998
# Test Credit Card Numbers for declined results:
#   5105105105105100  Master Card
#   5555555555554444  Master Card
#   4111111111111111  VISA
#   4012888888881881  VISA
#   378282246310005   American Express
#   371449635398431   American Express
# Valid Routing Numbers:
#   222371863, 307075259, 052000113


require 'mechanize'

class RemoteSecureNetTest < Test::Unit::TestCase

  @@virtual_terminal_inited = false

  def setup
    @gateway = SecureNetGateway.new(fixtures(:secure_net))
    init_virtual_terminal(fixtures(:secure_net_virtual_terminal)) unless @@virtual_terminal_inited
    
    @amount = 1000
    @declined_amount = 112
    @credit_card = credit_card('4111111111111111', :verification_value => '999')
    @check = check(:bank_name => 'Greenery', :routing_number => '222371863')
    @jimsmith = {
      :customer_id => 'jimsmith@example.com',
      :account_id  => '1',
      :first_name  => 'Jim',
      :last_name   => 'Smith'
    }
    
    @options = { 
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end
  

  #
  # ACH Transactions
  #
  
  def test_check_successful_purchase
    assert response = @gateway.purchase(@amount, @check, @options)
    assert_success response
    assert_equal 'Approved', response.message
  end
  
  # This doesn't pass because SecureNet's test account won't settle ACH transactions
  # def test_check_purchase_and_credit_settled
  #   assert purchase = @gateway.purchase(@amount, @check, @options)
  #   assert_success purchase
  #   assert_equal 'Approved', purchase.message
  #   settle_transactions
  #   assert credit = @gateway.credit(@amount, purchase.authorization, @check, @options)
  #   assert_success credit
  #   assert_equal 'Approved', credit.message
  # end

  def test_check_purchase_and_credit_not_settled
    assert purchase = @gateway.purchase(@amount, @check, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    assert credit = @gateway.credit(@amount, purchase.authorization, @check, @options)
    assert_failure credit
    assert_equal 'CREDIT CANNOT BE COMPLETED ON A UNSETTLED TRANSACTION', credit.message
  end

  def test_check_purchase_and_void_settled
    assert purchase = @gateway.purchase(@amount, @check, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    settle_transactions
    assert void = @gateway.void(@amount, purchase.authorization, @check, @options)
    assert_success void
    assert_equal 'Approved', void.message
  end

  def test_check_purchase_and_void_not_settled
    assert purchase = @gateway.purchase(@amount, @check, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    assert void = @gateway.void(@amount, purchase.authorization, @check, @options)
    assert_success void
    assert_equal 'Approved', void.message
  end
  
  def test_check_credit_with_bogus_reference
    assert credit = @gateway.credit(@amount, '123456', @check, @options)
    assert_failure credit
    assert_equal 'TRANSACTION ID DOES NOT EXIST FOR CREDIT', credit.message
  end

  def test_check_void_with_bogus_reference
    assert void = @gateway.void(@amount, '123456', @check, @options)
    assert_failure void
    assert_equal 'TRANSACTION ID DOES NOT EXIST FOR VOID', void.message
  end

  def test_check_credit_with_missing_reference
    assert credit = @gateway.credit(@amount, nil, @check, @options)
    assert_failure credit
    assert_equal 'PREVIOUS TRANSACTION ID IS REQUIRED', credit.message
  end

  def test_check_void_with_missing_reference
    assert void = @gateway.void(@amount, nil, @check, @options)
    assert_failure void
    assert_equal 'PREVIOUS TRANSACTION ID IS REQUIRED', void.message
  end

  # This is not failing like it supposed to 
  # def test_check_unsuccessful_purchase
  #   assert response = @gateway.purchase(@declined_amount, @check, @options)
  #   assert_failure response    
  #   assert_equal 'Declined  DO NOT HONOR', response.message
  # end

  def test_store_and_store_check
    response = @gateway.store( @check, @jimsmith )

    response = @gateway.store( @check, @jimsmith.merge!( :new_customer => false ) )
    puts response.inspect

    @gateway.unstore( @jimsmith[:customer_id] )
  end

  
  def test_store_and_unstore_check
    response = @gateway.store( @check, @jimsmith )
    assert_success response
    assert_equal 'New Account Added.', response.message

    response = @gateway.unstore( @jimsmith[:customer_id] )
    assert_success response
    assert_equal 'Customer is Deleted', response.message
  end

  def test_store_purchase_and_unstore_check
    @gateway.unstore( @jimsmith[:customer_id] )
    
    response = @gateway.store( @check, @jimsmith )
    assert_success response
    assert_equal 'New Account Added.', response.message
    
    @options.merge!(:customer_id => @jimsmith[:customer_id], :account_id => @jimsmith[:account_id])
    assert purchase = @gateway.purchase(@amount, nil, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message

    response = @gateway.unstore( @jimsmith[:customer_id] )
    assert_success response
    assert_equal 'Customer is Deleted', response.message
  end

  def test_store_purchase_void_and_unstore_check
    @gateway.unstore( @jimsmith[:customer_id] )
    
    response = @gateway.store( @check, @jimsmith )
    assert_success response
    assert_equal 'New Account Added.', response.message
    
    @options.merge!(:customer_id => @jimsmith[:customer_id], :account_id => @jimsmith[:account_id])
    assert purchase = @gateway.purchase(@amount, nil, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message

    assert void = @gateway.void(@amount, purchase.authorization, nil, @options)
    assert_success void
    assert_equal 'Approved', void.message

    response = @gateway.unstore( @jimsmith[:customer_id] )
    assert_success response
    assert_equal 'Customer is Deleted', response.message
  end
  
  #
  # Credit Card Transactions
  #
  
  def test_credit_card_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
  end

  def test_credit_card_unsuccessful_purchase
    assert response = @gateway.purchase(@declined_amount, @credit_card, @options)
    assert_failure response    
    assert_equal 'Declined  DO NOT HONOR', response.message
  end

  def test_credit_card_authorize_and_capture_amount_exact
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Approved', auth.message
    assert capture = @gateway.capture(@amount, auth.authorization, @credit_card, @options)
    assert_success capture
    assert_equal 'Approved', capture.message
  end

  def test_credit_card_purchase_and_credit_using_last_four_digits
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    settle_transactions
    @credit_card = credit_card(@credit_card.last_digits)
    assert credit = @gateway.credit(@amount, purchase.authorization, @credit_card, @options)
    assert_success credit
    assert_equal 'Approved', credit.message
  end

  def test_credit_card_authorize_level2
    @credit_card = credit_card('5581111111111119', :month => 12, :year => 2010, :type => 'mastercard', :verification_value => nil)
    @options.merge!({ :tax_amount => '1.00', :tax_status => 1, :po_number => '12345' })
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Approved', auth.message
  end

  def test_credit_card_purchase_level2
    @credit_card = credit_card('5581111111111119', :month => 12, :year => 2010, :type => 'mastercard', :verification_value => nil)
    @options.merge!({ :tax_amount => '1.00', :tax_status => 1, :po_number => '12345' })
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Approved', auth.message
  end

  def test_credit_card_authorize_and_capture_with_level2
    @credit_card = credit_card('5581111111111119', :month => 12, :year => 2010, :type => 'mastercard', :verification_value => nil)
    @options.merge!({ :tax_amount => '1.00', :tax_status => 1, :po_number => '12345' })
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Approved', auth.message
    assert capture = @gateway.capture(@amount, auth.authorization, @credit_card, @options)
    assert_success capture
    assert_equal 'Approved', capture.message
  end


  # This fails because the system is not functioning as the docuemtnation specifies.
  # A Credit transaction that has no Amount, should Credit for the amount of 
  # the original transaction.  Instead, we get a credit of 0.00
  # def test_credit_card_authorize_and_capture_amount_not_specified
  #   assert auth = @gateway.authorize(@amount, @credit_card, @options)
  #   assert_success auth
  #   assert_equal 'Approved', auth.message
  #   assert capture = @gateway.capture(nil, auth.authorization, @credit_card, @options)
  #   assert_equal @amount, (capture.params['amount'].to_f*100).to_i
  #   assert_success capture
  #   assert_equal 'Approved', capture.message
  # end

  def test_credit_card_authorize_and_capture_amount_low
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Approved', auth.message
    assert capture = @gateway.capture(@amount-100, auth.authorization, @credit_card, @options)
    assert_success capture
    assert_equal 'Approved', capture.message
  end

  # This should not be successful because you should not be able to Capture
  # for more than you Auth'ed.  The documentation says as much, but the system
  # doesn't function accordingly. 
  # def test_credit_card_authorize_and_capture_amount_too_high
  #   assert auth = @gateway.authorize(@amount, @credit_card, @options)
  #   assert_success auth
  #   assert_equal 'Approved', auth.message
  #   assert capture = @gateway.capture(@amount**2, auth.authorization, @credit_card, @options)
  #   assert_failure capture
  # end

  def test_credit_card_authorize_and_void
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Approved', auth.message
    assert void = @gateway.void(@amount, auth.authorization, @credit_card, @options)
    assert_success void
    assert_equal 'Approved', void.message
  end

  def test_credit_card_purchase_and_credit_settled
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    settle_transactions
    assert credit = @gateway.credit(@amount, purchase.authorization, @credit_card, @options)
    assert_success credit
    assert_equal 'Approved', credit.message
  end

  def test_credit_card_purchase_and_credit_not_settled
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    assert credit = @gateway.credit(@amount, purchase.authorization, @credit_card, @options)
    assert_failure credit
    assert_equal 'CREDIT CANNOT BE COMPLETED ON A UNSETTLED TRANSACTION', credit.message
  end

  def test_credit_card_purchase_and_credit_amount_exact
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    settle_transactions
    assert credit = @gateway.credit(@amount, purchase.authorization, @credit_card, @options)
    assert_success credit
    assert_equal 'Approved', credit.message
  end

  def test_credit_card_purchase_and_credit_amount_not_specified
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    settle_transactions
    assert credit = @gateway.credit(nil, purchase.authorization, @credit_card, @options)
    assert_failure credit
    assert_equal 'TRANSACTION AMOUNT IS REQUIRED', credit.message
  end

  def test_credit_card_purchase_and_credit_amount_low
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    settle_transactions
    assert credit = @gateway.credit(@amount-100, purchase.authorization, @credit_card, @options)
    assert_success credit
    assert_equal 'Approved', credit.message
  end

  def test_credit_card_purchase_and_credit_amount_too_high
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    settle_transactions
    assert credit = @gateway.credit(@amount*2, purchase.authorization, @credit_card, @options)
    assert_failure credit
    assert_equal 'CREDIT AMOUNT CANNOT BE GREATER THAN THE AUTHORIZED AMOUNT', credit.message
  end

  def test_credit_card_purchase_and_multiple_credits_exact
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    settle_transactions
    assert credit = @gateway.credit(@amount/2, purchase.authorization, @credit_card, @options)
    assert_success credit
    assert_equal 'Approved', credit.message
    assert credit = @gateway.credit(@amount/2, purchase.authorization, @credit_card, @options)
    assert_success credit
    assert_equal 'Approved', credit.message
  end

  def test_credit_card_purchase_and_multiple_credits_too_high
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    settle_transactions
    assert credit = @gateway.credit(@amount-100, purchase.authorization, @credit_card, @options)
    assert_success credit
    assert_equal 'Approved', credit.message
    assert credit = @gateway.credit(@amount, purchase.authorization, @credit_card, @options)
    assert_failure credit
    assert_equal 'CREDIT AMOUNT CANNOT BE GREATER THAN THE AUTHORIZED AMOUNT', credit.message
  end

  def test_credit_card_purchase_and_void_settled
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    settle_transactions
    assert void = @gateway.void(@amount, purchase.authorization, @credit_card, @options)
    assert_failure void
    assert_equal 'TRANSACTION CANNOT BE VOIDED AS ITS ALREADY SETTLED', void.message
  end

  def test_credit_card_purchase_and_void_not_settled
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    assert void = @gateway.void(@amount, purchase.authorization, @credit_card, @options)
    assert_success void
    assert_equal 'Approved', void.message
  end

  # Why is an amount needed to void?
  def test_credit_card_purchase_and_void_amount_not_specified
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    assert void = @gateway.void(nil, purchase.authorization, @credit_card, @options)
    assert_failure void
    assert_equal 'TRANSACTION AMOUNT IS REQUIRED', void.message
  end

  def test_credit_card_purchase_and_void_amount_low
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    assert void = @gateway.void(@amount-100, purchase.authorization, @credit_card, @options)
    assert_failure void
    assert_equal 'VOIDED AMOUNT CANNOT BE DIFFERENT THAN PREVIOUSLY AUTHORIZED AMOUNT', void.message
  end

  def test_credit_card_purchase_and_void_amount_high
    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message
    assert void = @gateway.void(@amount*2, purchase.authorization, @credit_card, @options)
    assert_failure void
    assert_equal 'VOIDED AMOUNT CANNOT BE DIFFERENT THAN PREVIOUSLY AUTHORIZED AMOUNT', void.message
  end

  def test_credit_card_capture_with_bogus_reference
    assert capture = @gateway.capture(@amount, '123456', @credit_card, @options)
    assert_failure capture
    assert_equal 'TRANSACTION ID DOES NOT EXIST FOR PRIOR_AUTH_CAPTURE', capture.message
  end

  def test_credit_card_credit_with_bogus_reference
    assert credit = @gateway.credit(@amount, '123456', @credit_card, @options)
    assert_failure credit
    assert_equal 'TRANSACTION ID DOES NOT EXIST FOR CREDIT', credit.message
  end

  def test_credit_card_void_with_bogus_reference
    assert void = @gateway.void(@amount, '123456', @credit_card, @options)
    assert_failure void
    assert_equal 'TRANSACTION ID DOES NOT EXIST FOR VOID', void.message
  end

  def test_credit_card_capture_with_missing_reference
    assert capture = @gateway.capture(@amount, nil, @credit_card, @options)
    assert_failure capture
    assert_equal 'PREVIOUS TRANSACTION ID IS REQUIRED', capture.message
  end

  def test_credit_card_credit_with_missing_reference
    assert credit = @gateway.credit(@amount, nil, @credit_card, @options)
    assert_failure credit
    assert_equal 'PREVIOUS TRANSACTION ID IS REQUIRED', credit.message
  end

  def test_credit_card_void_with_missing_reference
    assert void = @gateway.void(@amount, nil, @credit_card, @options)
    assert_failure void
    assert_equal 'PREVIOUS TRANSACTION ID IS REQUIRED', void.message
  end

  def test_store_and_unstore_credit_card
    response = @gateway.store( @credit_card, @jimsmith )
    assert_success response
    assert_equal 'New Account Added.', response.message

    response = @gateway.unstore( @jimsmith[:customer_id] )
    assert_success response
    assert_equal 'Customer is Deleted', response.message
  end

  def test_store_purchase_and_unstore_credit_card
    @gateway.unstore( @jimsmith[:customer_id] )
    
    response = @gateway.store( @credit_card, @jimsmith )
    assert_success response
    assert_equal 'New Account Added.', response.message
    
    @options.merge!(:customer_id => @jimsmith[:customer_id], :account_id => @jimsmith[:account_id])
    assert purchase = @gateway.purchase(@amount, nil, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message

    response = @gateway.unstore( @jimsmith[:customer_id] )
    assert_success response
    assert_equal 'Customer is Deleted', response.message
  end

  def test_store_purchase_credit_and_unstore_credit_card
    @gateway.unstore( @jimsmith[:customer_id] )
    
    response = @gateway.store( @credit_card, @jimsmith )
    assert_success response
    assert_equal 'New Account Added.', response.message
    
    @options.merge!(:customer_id => @jimsmith[:customer_id], :account_id => @jimsmith[:account_id])
    assert purchase = @gateway.purchase(@amount, nil, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message

    settle_transactions

    assert credit = @gateway.credit(@amount, purchase.authorization, nil, @options)
    assert_success credit
    assert_equal 'Approved', credit.message

    response = @gateway.unstore( @jimsmith[:customer_id] )
    assert_success response
    assert_equal 'Customer is Deleted', response.message
  end

  def test_store_purchase_void_and_unstore_credit_card
    @gateway.unstore( @jimsmith[:customer_id] )
    
    response = @gateway.store( @credit_card, @jimsmith )
    assert_success response
    assert_equal 'New Account Added.', response.message
    
    @options.merge!(:customer_id => @jimsmith[:customer_id], :account_id => @jimsmith[:account_id])
    assert purchase = @gateway.purchase(@amount, nil, @options)
    assert_success purchase
    assert_equal 'Approved', purchase.message

    assert void = @gateway.void(@amount, purchase.authorization, nil, @options)
    assert_success void
    assert_equal 'Approved', void.message

    response = @gateway.unstore( @jimsmith[:customer_id] )
    assert_success response
    assert_equal 'Customer is Deleted', response.message
  end




  def test_invalid_login
    gateway = SecureNetGateway.new(:login => '', :password => '')
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'SECURENET ID IS REQUIRED', response.message
  end
  
  private
  
  def settle_transactions
    @@terminal_form.submit(@@terminal_form.button_with(:name => 'UnsettledTransactionNew1:btn_Settle'))
    sleep 1 # Sometimes SecureNet needs a second for transactions to settle on their end
  end
  
  def init_virtual_terminal(credentials)
    self.class.init_virtual_terminal(credentials)
  end
  
  def self.init_virtual_terminal(credentials)
    WWW::Mechanize.new do |agent|
      url = 'https://terminal.securenet.com/demo'
      login_page = agent.get(url+'/login.aspx')
      login_form = login_page.form('Form1')
      login_form.field_with(:name => 'Multilogin1:txtUsername').value = credentials[:login]
      login_form.field_with(:name => 'Multilogin1:txtPassword').value = credentials[:password]
      login_form.submit(login_form.button_with(:name => 'Multilogin1:btnSubmit'))
      transactions_page = agent.get(url+'/Terminal/Unsettled_TransactionNew.aspx?m=6&Qid=0')
      @@terminal_form = transactions_page.form('Form1')
    end
  end
  
end