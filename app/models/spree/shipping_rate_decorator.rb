Spree::ShippingRate.class_eval do
  unloadable
  def name
    read_attribute(:name) || shipping_method.name
  end

  def admin_name
    read_attribute(:name) || begin
      if self.easy_post_rate_id.nil?
        shipping_method.name
      else
        "EasyPost: #{shipping_method.name}"
      end
    end
  end
end