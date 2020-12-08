require 'dry-struct'
require 'json-schema'
require 'json'
require 'pry'
require 'aws-sdk-schemas'
require 'aws-sdk-eventbridge'
require 'aws-sdk-kms'

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

schema_registry_client = Aws::Schemas::Client.new
event_bridge_client = Aws::EventBridge::Client.new
kms_client = Aws::KMS::Client.new

schema_response = schema_registry_client.describe_schema(registry_name: 'test', schema_name: 'json-schema-test', schema_version: '3')
schema = JSON.parse(schema_response.content)
p "Given event schema is #{schema}"

class EncryptedPayload < Dry::Struct
  transform_keys(&:to_sym)

  attribute :ciphertext_blob, Types::Strict::String
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

  ciphertext_blob = kms_client
    .encrypt(key_id: "alias/event-consumer-test", plaintext: stuffs.to_json)
    .then { |encryption| Base64.encode64(encryption.ciphertext_blob) }

  encrypted_something_sensitive = encrypted_struct.new(
    ciphertext_blob: ciphertext_blob,
    schema: schema_definition
  )
}

publish_something_sensitive = -> (something_sensitive) {
  encrypted_something_sensitive = encrypt.call(SomethingSensitive.new(something_sensitive))

  event_bridge_client.put_events({
    entries: [
      {
        time: Time.now,
        source: "test",
        resources: ["EventResource"],
        detail_type: "test",
        detail: encrypted_something_sensitive.to_h.to_json
      }
    ]
  })

  encrypted_something_sensitive
}

something_sensitive = {foo: 'bar'}
p "Given something_sensitive is #{something_sensitive}"

decrypted_event_validation_result = JSON::Validator.validate(schema.dig("definitions", "something_sensitive"), something_sensitive.to_json)
p "decrypted_event_validation_result prior to publishing is #{decrypted_event_validation_result}"

encrypted_something_sensitive = publish_something_sensitive.call(something_sensitive)
encrypted_event_validation_result = JSON::Validator.validate(schema, { encrypted_something_sensitive: encrypted_something_sensitive.to_h }.to_json)
p "encrypted_event_validation_result prior to publishing is #{encrypted_event_validation_result}"
p "encrypted_something_sensitive is #{encrypted_something_sensitive.to_h}"

event_json = { encrypted_something_sensitive: encrypted_something_sensitive.to_h }.to_json

# resp = event_bridge_client.put_events({
#   entries: [ # required
#     {
#       time: Time.now,
#       source: "test",
#       resources: ["EventResource"],
#       detail_type: "test",
#       detail: event_json
#     },
#   ],
# })

#  tt = kms_client.encrypt(key_id: "alias/event-consumer-test", plaintext: event_json)
#  ciphertext = Base64.encode64(tt.ciphertext_blob)
#  decryption_result = kms_client.decrypt(ciphertext_blob: Base64.decode64(ciphertext))
#  json = decryption_result.plaintext
binding.pry

decrypt = -> (encrypted_event) {
  struct = Object.const_get(encrypted_event.schema.gsub('#/definitions/', '').camelcase)
  struct.new(foo: 'bar')
}

consume_something_sensitive = -> (event_json) {
  event = EncryptedSomethingSensitive.new(JSON.parse(event_json)['encrypted_something_sensitive'])
  decrypt.call(event)
}

p "result of consuming event #{consume_something_sensitive.call(event_json).to_h}"

# binding.pry
