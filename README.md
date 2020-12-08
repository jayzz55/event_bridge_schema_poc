# Event bridge schema POC

This repo is to spike the event bridge schemas where events have encrypted blobs

> If we were to use event bridge as an event bus, we need to use the event bridge schema registry to define the format of our events for relevant services to consume. Given that we can't have guarantee of event payloads being encrypted, we need to be able to bake encrypted payloads into our event schemas ourselves, but how do we define the schema of the encrypted blob (within the schema definition stored in the registry) so that consumers can know what they are consuming

See: https://trello.com/c/KfYfb22c/375-poc-defining-event-bridge-schemas-where-events-have-encrypted-blobs-as-part-of-the-payload

To run the app:
1. `bundle install`
2. run `awsauth` and use the dev env
3. run `ruby main.rb`

Use `binding.pry` to pry around the code :)

## Cleanup

Manually remove following AWS resources:
* KMS event-consumer-test
* EventRegistry rules pattern
* Generated SAM cloudformation - event consumer lambda
