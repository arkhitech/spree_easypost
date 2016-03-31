class CreateEasypostShipmentResponses < ActiveRecord::Migration
  def change
    create_table :spree_easypost_shipment_responses do |t|
      t.references :shipment
      t.text  :buy_response
    end
  end
end
