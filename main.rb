require 'dry-struct'
require 'json-schema'
require 'json'
require 'pry'
require 'aws-sdk-schemas'

class String
  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end

  def camelcase
    self.split('_').collect(&:capitalize).join
  end
end

module Types
  include Dry.Types()
end

client = Aws::Schemas::Client.new
schema_response = client.describe_schema(registry_name: 'test', schema_name: 'json-schema-test', schema_version: '1')
schema = JSON.parse(schema_response.content)
p "Given event schema is #{schema}"

class EncryptedPayload < Dry::Struct
  transform_keys(&:to_sym)

  attribute :encrypted_data, Types::Strict::String
  attribute :iv, Types::Strict::String
  attribute :data_key, Types::Strict::String
  attribute :master_key_alias, Types::Strict::String
end

class EncryptedSomethingSensitive < EncryptedPayload
  attribute :schema, Types::String.enum("#/definitions/something_sensitive")
end

class SomethingSensitive < Dry::Struct
  transform_keys(&:to_sym)

  attribute :foo, Types::Strict::String
end

encrypt = -> (stuffs) {
  encrypted_struct = Object.const_get("Encrypted#{stuffs.class}")
  schema_definition = "#/definitions/#{stuffs.class.name.underscore}"

  encrypted_something_sensitive = encrypted_struct.new(
    encrypted_data: "something",
    iv: "something",
    data_key: "something",
    master_key_alias: "something",
    schema: schema_definition
  )
}

publish_something_sensitive = -> (something_sensitive) {
  encrypt.call(SomethingSensitive.new(something_sensitive))
}

something_sensitive = {foo: 'bar'}
p "Given something_sensitive is #{something_sensitive}"

decrypted_event_validation_result = JSON::Validator.validate(schema.dig("definitions", "something_sensitive"), something_sensitive.to_json)
p "decrypted_event_validation_result prior to publishing is #{decrypted_event_validation_result}"

encrypted_something_sensitive = publish_something_sensitive.call(something_sensitive)
encrypted_event_validation_result = JSON::Validator.validate(schema, { encrypted_something_sensitive: encrypted_something_sensitive.to_h }.to_json)
p "encrypted_event_validation_result prior to publishing is #{encrypted_event_validation_result}"
p "encrypted_something_sensitive is #{encrypted_something_sensitive.to_h}"

decrypt = -> (encrypted_event) {
  struct = Object.const_get(encrypted_event.schema.gsub('#/definitions/', '').camelcase)
  struct.new(foo: 'bar')
}

consume_something_sensitive = -> (event_json) {
  event = EncryptedSomethingSensitive.new(JSON.parse(event_json)['encrypted_something_sensitive'])
  decrypt.call(event)
}

event_json = { encrypted_something_sensitive: encrypted_something_sensitive.to_h }.to_json

p "result of consuming event #{consume_something_sensitive.call(event_json).to_h}"

# binding.pry
