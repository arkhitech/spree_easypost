Spree::Stock::Estimator.class_eval do
  def shipping_rates(package, frontend_only = true)
    rates = calculate_shipping_rates(package)
    unless rates.empty? || rates.nil?
      #rates.select! { |rate| rate.shipping_method.frontend? } if frontend_only
      package.shipping_rates = rates
      rates = shipping_rates_via_easypost(package, frontend_only)

#      choose_default_shipping_rate(rates)
      sort_shipping_rates(rates)
    else
      []
    end
  end
  
  def shipping_rates_via_easypost(package, frontend_only = true)
    order = package.order
    from_address = process_address(package.stock_location)
    to_address = process_address(order.ship_address)
    parcel = build_parcel(package)
    
    shipment = build_shipment(from_address, to_address, parcel, package)
    rates = shipment.rates#.sort_by { |r| r.rate.to_i }
    
    spree_shipping_rates = package.shipping_rates
    new_easypost_shipping_rates = []
    if rates.any?
      rates.each do |rate|
        found_match = false
        spree_shipping_rates.each do |spree_shipping_rate|
          if spree_shipping_rate.shipping_method.admin_name == "#{rate.carrier} #{rate.service}"
            spree_shipping_rate.easy_post_shipment_id = rate.shipment_id
            spree_shipping_rate.easy_post_rate_id = rate.id            
            spree_shipping_rate.cost = rate.rate
            
            #spree_easypost_shipping_rates << spree_shipping_rate
            found_match = true
          end
        end
        if !found_match
          #add the non-matching shipping rate from easypost to the backend but not front end
          new_easypost_shipping_rates << Spree::ShippingRate.new(
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
      if spree_shipping_rate.easy_post_rate_id.nil? && spree_shipping_rate.shipping_method.admin_name.present?
        predefined_package_name = spree_shipping_rate.shipping_method.admin_name
        begin
          parcel = build_predefined_parcel(package, predefined_package_name)
          shipment = build_shipment(from_address, to_address, parcel)            
          rates = shipment.rates        
          if rates.any?
            updated_first = false
            rates.each do |rate|
              unless updated_first
                spree_shipping_rate.easy_post_shipment_id = rate.shipment_id
                spree_shipping_rate.easy_post_rate_id = rate.id            
                spree_shipping_rate.cost = rate.rate
                updated_first = true
              else              
                new_easypost_shipping_rates << Spree::ShippingRate.new(
                  :name => spree_shipping_rate.name,#"#{rate.carrier} #{rate.service} - #{predefined_package_name}",
                  :cost => rate.rate,
                  #shipping_method_id: spree_shipping_rate.shipping_method.id,
                  :easy_post_shipment_id => rate.shipment_id,
                  :easy_post_rate_id => rate.id
                )
              end
            end
          end
        rescue EasyPost::Error => e
          puts "Got error for: #{predefined_package_name}, #{e.message}\n#{e.backtrace.join("\n")}"
        end
      end
    end
    new_easypost_shipping_rates.each do |new_easypost_shipping_rate|
      package.shipping_rates << new_easypost_shipping_rate
    end
    package.shipping_rates
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
    ep_address_attrs[:country] = address.country && address.country.iso3
    ep_address_attrs[:zip] = address.zipcode
    ep_address_attrs[:phone] = address.phone

    ::EasyPost::Address.create(ep_address_attrs)
  end

  def build_parcel(package)
    total_weight = package.order.weight ||= package.contents.sum do |item|
      item.quantity * item.variant.ship_weight
    end
    width = package.order.width
    height = package.order.height
    length = package.order.length
    
    unless width.nil? && height.nil? && length.nil?
      parcel = ::EasyPost::Parcel.create(
        :weight => total_weight,
        :height => height,
        :length => length,
        :width => width
      )
    else
      parcel = ::EasyPost::Parcel.create(
        :weight => total_weight
      )
    end
  end
  def build_predefined_parcel(package, predefined_package_name)
    total_weight = package.contents.sum do |item|
      item.quantity * item.variant.ship_weight
    end
    parcel = ::EasyPost::Parcel.create(
     predefined_package: predefined_package_name,  weight: total_weight
    )
  end
  
  def build_shipment(from_address, to_address, parcel, package=nil)
    signature_required = package.order.signature_required unless package.nil?
    if signature_required
      shipment = ::EasyPost::Shipment.create(
        :to_address => to_address,
        :from_address => from_address,
        :parcel => parcel,
        :delivery_confirmation => 'SIGNATURE'
      )
    else
      shipment = ::EasyPost::Shipment.create(
      :to_address => to_address,
      :from_address => from_address,
      :parcel => parcel
    )
    end
  end

end
