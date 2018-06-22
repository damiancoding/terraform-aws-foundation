/**
 * ## Test Discourse on a Single-Node ASG
 *
 */

variable "name" {
  default = "discourse-asg-test"
}

variable "region" {
  default = "us-east-1"
}

variable "ssh_pubkey" {
  default     = "./id_rsa.pub"
  description = "The path to the SSH pub key to use"
}

variable "dns_zone_name" {
  description = "The name of the DNS zone on Route53 (example.com), to create records in for Discourse"
  type        = "string"
}

variable "discourse_name" {
  description = "To generate the DNS record for Discourse, prefix the zone"
  default     = "discourse"
  type        = "string"
}

variable "discourse_registry_name" {
  description = "To generate the DNS record for the docker registry, prefix the zone"
  default     = "registry"
  type        = "string"
}

variable "root_volume_size" {
  default     = "30"
  description = "GB of root data volume for the instance, make it larger than usual for docker builds"
}

provider "aws" {
  region = "${var.region}"
}

data "aws_availability_zones" "available" {}

module "ubuntu-xenial-ami" {
  source  = "../../modules/ami-ubuntu"
  release = "16.04"
}

resource "aws_key_pair" "main" {
  key_name   = "${var.name}"
  public_key = "${file(var.ssh_pubkey)}"
}

resource "aws_eip" "discourse" {
  vpc = true
}

resource "aws_security_group" "discourse-elb" {
  name        = "discourse-elb"
  vpc_id      = "${module.vpc.vpc_id}"
  description = "Security group for the discourse ELB"
}

module "elb-http-rule" {
  source            = "../../modules/single-port-sg"
  port              = 80
  description       = "Allow ingress for HTTP, port 80 (TCP), thru the ELB"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.discourse-elb.id}"
}

module "elb-https-rule" {
  source            = "../../modules/single-port-sg"
  port              = 443
  description       = "Allow ingress for HTTPS, port 443 (TCP), thru the ELB"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.discourse-elb.id}"
}

module "elb-discourse-ssh-rule" {
  source            = "../../modules/single-port-sg"
  port              = 22
  description       = "Allow ingress for Git over SSH, port 22 (TCP), thru the ELB"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.discourse-elb.id}"
}

module "elb-open-egress-rule" {
  source            = "../../modules/open-egress-sg"
  security_group_id = "${aws_security_group.discourse-elb.id}"
}

module "discourse-asg" {
  source        = "../../modules/single-node-asg"
  name_prefix   = "${var.name}"
  name_suffix   = "discourse-server"
  region        = "${var.region}"
  key_name      = "${aws_key_pair.main.key_name}"
  ami           = "${module.ubuntu-xenial-ami.id}"
  instance_type = "t2.medium"
  subnet_id     = "${module.vpc.public_subnet_ids[0]}"

  security_group_ids    = ["${aws_security_group.discourse.id}"]
  root_volume_size      = "${var.root_volume_size}"
  data_volume_encrypted = false

  init_prefix = <<END_INIT
apt-get update
${module.init-install-awscli.init_snippet}
${module.init-install-ops.init_snippet}
END_INIT

  init_suffix = <<END_INIT
aws ec2 associate-address --allocation-id=${aws_eip.discourse.id} --instance-id=$$(ec2metadata --instance-id) --allow-reassociation --region=${var.region}

mkdir -p /var/discourse
mount /dev/xvdf1 /var/discourse

cp /etc/fstab /etc/fstab.orig
echo "LABEL=discourse            /var/discourse  ext4   defaults,nofail     0 2" >> /etc/fstab

wget -qO- https://get.docker.com/ | sh
cat >/etc/rc.local <<END_RC_LOCAL
#!/bin/sh -e
/var/discourse/launcher rebuild app
END_RC_LOCAL

END_INIT


/* the below code is unused after Manny provided new init_suffix. */
/*
  init_suffix = <<END_INIT
mkdir -p /gitlab
mount /dev/xvdf1 /gitlab

cp /etc/fstab /etc/fstab.orig
echo "LABEL=gitlab            /gitlab  ext4   defaults,nofail     0 2" >> /etc/fstab

apt-get install -y docker docker.io
${module.init-gitlab-docker.init_snippet}
${module.init-gitlab-runner.init_snippet}
END_INIT
*/

}

module "init-install-awscli" {
  source = "../../modules/init-snippet-install-awscli"
}

module "init-install-ops" {
  source = "../../modules/init-snippet-install-ops"
}

/* FIXME: create ../../modules/init-snippet-discourse-docker based on the
* gitlab one. Better yet, use Discourse's launcher script which takes care of
* setting up the docker.
*
* The below code is unused after Manny provided a new init_suffix for the
* module discourse-asg. */
/*
module "init-discourse-docker" {
  source        = "../../modules/init-snippet-gitlab-docker"
  discourse_domain = "${var.dns_zone_name}"
}
*/

/* unused, after Manny provided new init_suffix for discourse-asg: */
/*
module "init-discourse-runner" {
  source = "../../tf-modules/init-snippet-exec"

  init = <<END_INIT
mkdir /etc/gitlab-runner
cp /gitlab/gitlab-runner-config.toml /etc/gitlab-runner/config.toml
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh |  bash
apt-get install -y gitlab-runner
END_INIT
}
*/

module "vpc" {
  source              = "../../modules/vpc-scenario-1"
  azs                 = ["${slice(data.aws_availability_zones.available.names, 0, 1)}"]
  name_prefix         = "${var.name}"
  cidr                = "192.168.0.0/16"
  public_subnet_cidrs = ["192.168.0.0/16"]
  region              = "${var.region}"
}

resource "aws_security_group" "discourse" {
  name        = "discourse-asg"
  vpc_id      = "${module.vpc.vpc_id}"
  description = "Security group for the single-node autoscaling group"
}

module "ssh-rule" {
  source            = "../../modules/ssh-sg"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.discourse.id}"
}

module "http-rule" {
  source            = "../../modules/single-port-sg"
  port              = 80
  description       = "Allow ingress for HTTP, port 80 (TCP)"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.discourse.id}"
}

module "https-rule" {
  source            = "../../modules/single-port-sg"
  port              = 443
  description       = "Allow ingress for HTTPS, port 443 (TCP)"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.discourse.id}"
}

module "discourse-ssh-rule" {
  source            = "../../modules/single-port-sg"
  port              = 8022
  description       = "Allow ingress for Git over SSH, port 8022 (TCP)"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.discourse.id}"
}

module "open-egress-rule" {
  source            = "../../modules/open-egress-sg"
  security_group_id = "${aws_security_group.discourse.id}"
}

##################
## DNS setup

resource "aws_route53_zone" "selected" {
  name = "${var.dns_zone_name}"
}

resource "aws_route53_record" "discourse" {
  zone_id = "${aws_route53_zone.selected.zone_id}"
  name    = "${var.discourse_name}.${aws_route53_zone.selected.name}"
  type    = "CNAME"
  ttl     = "300"
  records = ["${module.discourse-asg.asg_name}"]
}

resource "aws_route53_record" "registry" {
  zone_id = "${aws_route53_zone.selected.zone_id}"
  name    = "${var.discourse_registry_name}.${aws_route53_zone.selected.name}"
  type    = "CNAME"
  ttl     = "300"
  records = ["${module.discourse-asg.asg_name}"]
}

##################
## Outputs

output "region" {
  value       = "${var.region}"
  description = "region deployed to"
}

output "discourse_asg_name" {
  value       = "${var.name}-discourse-asg-${element(data.aws_availability_zones.available.names, 0)}"
  description = "name of the Discourse autoscaling group"
}

output "discourse_url" {
  value       = "${aws_route53_record.discourse.name}"
  description = "URL to Discourse"
}

output "registry_url" {
  value       = "${aws_route53_record.registry.name}"
  description = "URL to docker image registry"
}
