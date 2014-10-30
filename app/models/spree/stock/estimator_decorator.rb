Spree::Stock::Estimator.class_eval do
  def shipping_rates(package, frontend_only = true)
        rates = calculate_shipping_rates(package)
        rates.select! { |rate| rate.shipping_method.frontend? } if frontend_only
        package.shipping_rates = rates
        rates = shipping_rates_via_easypost(package, frontend_only)
        
        choose_default_shipping_rate(rates)
        sort_shipping_rates(rates)
  end
  
  def shipping_rates_via_easypost(package, frontend_only = true)
    order = package.order
    from_address = process_address(package.stock_location)
    to_address = process_address(order.ship_address)
    parcel = build_parcel(package)
    
    shipment = build_shipment(from_address, to_address, parcel)
    rates = shipment.rates#.sort_by { |r| r.rate.to_i }
    
    spree_shipping_rates = package.shipping_rates
    
    spree_easypost_shipping_rates = []
    
    if rates.any?
      rates.each do |rate|
        found_match = false
        spree_shipping_rates.each do |spree_shipping_rate|
          if spree_shipping_rate.shipping_method.admin_name == "#{rate.carrier} #{rate.service}"
            spree_shipping_rate.easy_post_shipment_id = rate.shipment_id
            spree_shipping_rate.easy_post_rate_id = rate.id            
            spree_shipping_rate.cost = rate.rate
            
            spree_easypost_shipping_rates << spree_shipping_rate
            found_match = true
          end
        end
        if !found_match && !frontend_only
          #add the non-matching shipping rate from easypost to the backend but not front end
          spree_easypost_shipping_rates << Spree::ShippingRate.new(
            :name => "#{rate.carrier} #{rate.service}",
            :cost => rate.rate,
            :easy_post_shipment_id => rate.shipment_id,
            :easy_post_rate_id => rate.id
          )
        end
      end
    end
    #for all shipping rates, for which the corresponding rates were not found, use
    #the admin_name as the parcel size
    package.shipping_rates.each do |spree_shipping_rate|
      if spree_shipping_rate.easy_post_rate_id.nil?
        predefined_package_name = spree_shipping_rate.shipping_method.admin_name
        parcel = build_predefined_parcel(package, predefined_package_name)
        shipment = build_shipment(from_address, to_address, parcel)            
        rates = shipment.rates
        if rates.any?
          rates.each do |rate|
            spree_easypost_shipping_rates << Spree::ShippingRate.new(
              :name => spree_shipping_rate.name,#"#{rate.carrier} #{rate.service} - #{predefined_package_name}",
              :cost => rate.rate,
              :easy_post_shipment_id => rate.shipment_id,
              :easy_post_rate_id => rate.id
            )
          end
        end
      end
    end
    spree_easypost_shipping_rates
  end

  private

  def process_address(address)
    ep_address_attrs = {}
    # Stock locations do not have "company" attributes,
    ep_address_attrs[:company] = if address.respond_to?(:company)
      address.company
    else
      Spree::Config[:site_name]
    end
    ep_address_attrs[:name] = address.full_name if address.respond_to?(:full_name)
    ep_address_attrs[:street1] = address.address1
    ep_address_attrs[:street2] = address.address2
    ep_address_attrs[:city] = address.city
    ep_address_attrs[:state] = address.state ? address.state.abbr : address.state_name
    ep_address_attrs[:zip] = address.zipcode
    ep_address_attrs[:phone] = address.phone

    ::EasyPost::Address.create(ep_address_attrs)
  end

  def build_parcel(package)
    total_weight = package.contents.sum do |item|
      item.quantity * item.variant.weight
    end 
    parcel = ::EasyPost::Parcel.create(
      :weight => total_weight
    )
  end
  def build_predefined_parcel(package, package_name)
    total_weight = package.contents.sum do |item|
      item.quantity * item.variant.weight
    end 
    parcel = ::EasyPost::Parcel.create(
     :predefined_package => 'FlatRatePaddedEnvelope',  :weight => total_weight
    )    
  end
  
  def build_shipment(from_address, to_address, parcel)
    shipment = ::EasyPost::Shipment.create(
      :to_address => to_address,
      :from_address => from_address,
      :parcel => parcel
    )
  end

end
