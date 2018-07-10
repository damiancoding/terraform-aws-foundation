.PHONY: generate-ssh-key render-tfvars render-tfvars-step-2 network plan apply test destroy clean-files clean

# all the tls things can be removed, because we don't use the ELB any more, and discourse has built in support for Let's Encrypt.
#
# also, you can remove the ssh_config stuff, because that's only for using git with gitlab repositories via ssh.

.DEFAULT_GOAL = help

## Use ssh-keygen to generate a keypair for SSH
generate-ssh-key:
	@ssh-keygen -q -N "" -b 4096 -C "test" -f ./id_rsa

## Use envsubst and project.env to render terraform-tfvars.tpl into terraform.tfvars
render-tfvars:
	@. ./vars.env && ./checkvars
	@. ./vars.env && envsubst <terraform-tfvars.tpl > terraform.tfvars

# TODO: move generate-ssh-key before render-tfvars (also in the README) and
# join both steps in render-tfvars together.
## write out a tfvars file for a test deploy
render-tfvars-step-2:
	@echo "ssh_pubkey = \"./id_rsa.pub\"" >> terraform.tfvars

## Use Terraform to create the VPC and core network resources in a specific order
network:
	@terraform init
	@terraform plan -out=tf.out -target=module.vpc.module.public-subnets
	@terraform apply tf.out
	@terraform plan -out=tf.out -target=module.vpc.module.public-gateway
	@terraform apply tf.out
	@terraform plan -out=tf.out -target=module.vpc
	@terraform apply tf.out
	@rm -rf tf.out

## Use Terraform to generate a planfile tf.out
plan:
	@terraform plan -out=tf.out

## Use Terraform to apply the tf.out planfile
apply:
	@terraform apply tf.out

## use ops cli tool to lookup the public IP of the Discourse instance
get-ip:
	@ops aws ec2 asg ips -r $$(terraform output region) $$(terraform output discourse_asg_name)

create-activate-swap:
	@ssh data-ops-discourse "sudo dd if=/dev/zero of=/var/swap.file bs=1M count=2048 && sudo mkswap /var/swap.file && sudo chmod 600 /var/swap.file && sudo swapon /var/swap.file"

## SSH to the discourse server and halt the host so it is terminated
terminate-discourse-server:
	@ssh data-ops-discourse "sudo halt"

## SSH to the discourse server and register the CI runner with the server
register-discourse-runner:
	@ssh data-ops-discourse "sudo discourse-runner register"

## SSH to the discourse server and cat the runner's config file
cat-discourse-runner-config:
	@ssh data-ops-discourse "sudo cat /etc/discourse-runner/config.toml"

## SSH to the discourse server and copy the runner's config file to the EBS volume
copy-discourse-runner-config:
	@ssh data-ops-discourse "sudo cp /etc/discourse-runner/config.toml /discourse/discourse-runner-config.toml && ls -Alh /discourse/"

## Login to docker registry
docker-login:
	@docker login $$(terraform registry_url)

## Use Terraform to destory all resources in the test env
destroy:
	@terraform destroy -force

clean: destroy clean-files

## rm -rf everything
clean-files:
	@rm -rf terraform.tfstate terraform.tfstate.backup .terraform
	@rm -rf id_rsa id_rsa.pub ssh_config
	@rm -rf tf.out terraform.tfvars

## Show help screen.
help:
	@echo "Please use \`make <target>' where <target> is one of\n\n"
	@awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "%-30s %s\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)
