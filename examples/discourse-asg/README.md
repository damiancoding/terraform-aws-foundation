## Discourse on AWS ASG w/ Terraform

### What this is

This Terraform project sets up Discourse (some manual steps required):

* runs a single EC2 instance on AWS
* the EC2 instance is in an auto-scaling group, so AWS will re-create the node
  if it fails in specific ways
* use docker to run Discourse "all-in-one"
* install Discourse
* include SSL via Let's Encrypt
* integrate with SSH
* integrate with Route53 for DNS
* keep it simple, but provide a lot of HA

Manual steps:

* ...
* ...
* ...


## Deployment

### Define your deployment parameters

First, edit `vars.env` and review/update the variables defined in there

### Initial Deploy

Run the following make targets:

```
ᐅ make generate-ssh-key
ᐅ make render-tfvars
ᐅ make network
ᐅ make plan
ᐅ make apply
```

#### SSH Config

Add the hosts entry for SSH found in the `ssh_config` file to `~/.ssh/config`.

### Initial Setup

The following steps need to be done manually:

* ...
* ...
* ...
