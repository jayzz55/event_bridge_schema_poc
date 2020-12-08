require 'dry-struct'
require 'json-schema'
require 'json'
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

def lambda_handler(event:, context:)
  schema_registry_client = Aws::Schemas::Client.new
  kms_client = Aws::KMS::Client.new

  p "#############################"
  encrypted_something_sensitive = EncryptedSomethingSensitive.new(event.fetch('detail'))

  something_sensitive_struct = Object.const_get(
    encrypted_something_sensitive.schema.gsub('#/definitions/', '').camelcase
  )

  something_sensitive_hash = Base64.decode64(encrypted_something_sensitive.ciphertext_blob)
    .then { |ciphertext_blob| kms_client.decrypt(ciphertext_blob: ciphertext_blob) }
    .then { |decryption_result| decryption_result.plaintext }
    .then { |json| JSON.parse(json) }

  something_sensitive = something_sensitive_struct.new(something_sensitive_hash)


  # Normally you don't want to log the decrypted stuffs.
  # This is done to quickly check that the lambda is working as intended.
  # Please don't do this logging in production!!!!.
  p "SomethingSensitive is #{something_sensitive.to_h.to_json}"
  p "#############################"

  {
    statusCode: 200,
    body: {
      message: "Hello World!",
      # location: response.body
    }.to_json
  }
end
