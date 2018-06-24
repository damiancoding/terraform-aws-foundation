## Discourse on AWS ASG w/ Terraform

FIXME: go through this description and see if it's accurate.

### What is this

Describe this setup of Discourse:

* runs a single EC2 instance on AWS
* the EC2 instance is in an auto-scaling group, so AWS will re-create the node if it fails in specific ways
* use docker to run Discourse "all-in-one"
* install Discourse # FIXME: fix description
* include SSL
* integrate with SSH
* integrate with Route53 for DNS
* keep it simple, but provide a lot of HA


## The Discourse demo

This Terraform environment also serves as a great demo of Discourse's features and the basics of CI/CD. This next section will step through the Discourse demo.

### Define your Deployment

First, edit `vars.env` and review/update the variables defined there-in.


### Initial Deploy

Then, we run some make targets:

*Note:*
After the `make upload-tls-certs` step you can either manually copy the `ssl-arn` as instructed, or download the `jl` command from [here](https://github.com/chrisdone/jl/releases) and then run the following command in your terminal:
```
echo "ssl_arn = " `jl 'get "CertificateArn"' upload-gen-cert.json` >> terraform.tfvars
```

```
# ᐅ make render-tls-configs # FIXME: delete
ᐅ make render-tfvars
ᐅ make generate-ssh-key
# ᐅ make install-cfssl # FIXME: delete
# ᐅ make generate-tls-certs # FIXME: delete
# ᐅ make upload-tls-certs # FIXME: delete
ᐅ make render-tfvars-step-2
ᐅ make network
ᐅ make plan
ᐅ make apply
# ᐅ make render-ssh-config # FIXME: delete
```
#### SSH Config

Add the hosts entry for SSH found in the `ssh_config` file to `~/.ssh/config`.

### Initial Setup

Then, you will want to do the following:

* open the URL to the new Discourse instance in your browser
* setup a password in the TOFU ("trust on first" use workflow)
    * go to the Discourse URL with your browser
* login as `root` and that password you just set
* go to the admin area, then "settings" -> "runners"
* copy the Runner Registration Token shown on the runners page
* run `make register-discourse-runner`, you should see something like the output below. use `http://localhost` as the "discourse-ci coortinator URL", paste the registration token copied from the runners page, and run the `docker` executor with a default image you are happy with (we use `alpine` in this example here).

#### example runner registration

# FIXME: fix this section
```
Running in system-mode.

Please enter the gitlab-ci coordinator URL (e.g. https://gitlab.com/):
http://localhost
Please enter the gitlab-ci token for this runner:
WsYr4zLeW9wZSqvK7-Md
Please enter the gitlab-ci description for this runner:
on-host-docker-executor
Please enter the gitlab-ci tags for this runner (comma separated):
docker
Whether to run untagged builds [true/false]:
[false]: true
Whether to lock the Runner to current project [true/false]:
[true]: false
Registering runner... succeeded                     runner=Wsy4UZLe
Please enter the executor: virtualbox, kubernetes, shell, ssh, parallels, docker+machine, docker-ssh+machine, docker, docker-ssh:
docker
Please enter the default Docker image (e.g. ruby:2.1):
alpine:3.7
Runner registered successfully. Feel free to start it, but if it's running already the config should be automatically reloaded! 
```

#### Create a new user for yourself

* "regular" user (not admin)
* check/enable "can create groups"

#### Login as the new user

* generate an SSH keypair
* add the public key to your Discourse user profile

#### Setup New Groups

* create a new group `ops`
* create a new project `default-build-image`
* create a new group `web`
* add a file to the project, commit to `master`
* confirm the clone URLs look correct
* test the repo, clone it to your localhost over SSH and then HTTPS



### Integrated Docker Image Registry

#### Docker login:

```
ᐅ docker login registry.dev-sandbox.fpcomplete.com
Username: root
Password: 
Email: 
WARNING: login credentials saved in /home/user/.docker/config.json
Login Succeeded
```

Tag & push an image:

```
ᐅ docker tag 3c82203aab43 registry.dev-sandbox.fpcomplete.com/root/my-awesome-project:foobar
ᐅ docker push registry.dev-sandbox.fpcomplete.com/root/my-awesome-project:foobar
The push refers to a repository [registry.dev-sandbox.fpcomplete.com/root/my-awesome-project] (len: 1)
3c82203aab43: Pushed 
b2189dc83d7f: Pushed 
foobar: digest: sha256:3e8bfefbc2da87ef3b459db4c5edb4fb87410c5a4d8d411b98d086b009f380db size: 2152
```
