Spree::Shipment.class_eval do
  unloadable
  state_machine.before_transition :to => :shipped, :do => :buy_easypost_rate

  has_one :easypost_shipment_response, class_name: 'Spree::EasypostShipmentResponse'
  
#  def tracking_url
#    nil # TODO: Work out how to properly generate this
#  end

  private

  def selected_easy_post_rate_id
    selected_shipping_rate.easy_post_rate_id
  end

  def selected_easy_post_shipment_id
    selected_shipping_rate.easy_post_shipment_id
  end

  def easypost_shipment
    @ep_shipment ||= EasyPost::Shipment.retrieve(selected_easy_post_shipment_id)
  end

  def buy_easypost_rate
    if selected_easy_post_rate_id.nil?
      #the desired shipping method is not available on easypost
      return
    end
    rate = easypost_shipment.rates.find do |rate|
      rate.id == selected_easy_post_rate_id
    end
    
    easypost_shipment.buy(rate)
    if easypost_shipment.tracking_code.present?
      if self.order.insurance
        easypost_shipment.insure(self.order.total)
      end
      self.tracking = easypost_shipment.tracking_code
      self.create_easypost_shipment_response(buy_response: easypost_shipment.as_json)
    end
  end
end