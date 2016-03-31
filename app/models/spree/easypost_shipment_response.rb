module Spree
  class EasypostShipmentResponse < Spree::Base
    serialize :buy_response, JSON
    belongs_to :shipment, class_name: 'Spree::Shipment'
    def shipping_label
      buy_response['postage_label']['label_url']
    end
  end
end