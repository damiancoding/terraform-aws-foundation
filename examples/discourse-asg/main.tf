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

resource "aws_iam_role_policy" "associate_eip" {
  role = "${module.discourse-asg.asg_iam_role_name}"
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "ec2:AssociateAddress",
            "Resource": "*"
        }
    ]
}
POLICY
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


}

module "init-install-awscli" {
  source = "../../modules/init-snippet-install-awscli"
}

module "init-install-ops" {
  source = "../../modules/init-snippet-install-ops"
}

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

module "open-egress-rule" {
  source            = "../../modules/open-egress-sg"
  security_group_id = "${aws_security_group.discourse.id}"
}

##################
## DNS setup

data "aws_route53_zone" "selected" {
  name = "${var.dns_zone_name}"
}

resource "aws_route53_record" "discourse" {
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name    = "${var.discourse_name}.${data.aws_route53_zone.selected.name}"
  type    = "A"
  ttl     = "300"
  records = ["${aws_eip.discourse.public_ip}"]
}

##################
## SES SMTP setup

resource "aws_ses_domain_identity" "main" {
  domain = "${var.discourse_name}.${data.aws_route53_zone.selected.name}"
}

resource "aws_route53_record" "amazonses_verification_record" {
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name    = "_amazonses.${aws_ses_domain_identity.main.id}"
  type    = "TXT"
  ttl     = "600"
  records = ["${aws_ses_domain_identity.main.verification_token}"]
}

resource "aws_ses_domain_identity_verification" "main" {
  domain     = "${aws_ses_domain_identity.main.id}"
  depends_on = ["aws_route53_record.amazonses_verification_record"]
}

resource "aws_ses_domain_dkim" "main" {
  domain = "${aws_ses_domain_identity.main.domain}"
}

resource "aws_route53_record" "dkim_amazonses_verification_record" {
  count   = 3
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name    = "${element(aws_ses_domain_dkim.main.dkim_tokens, count.index)}._domainkey.${var.discourse_name}.${data.aws_route53_zone.selected.name}"
  type    = "CNAME"
  ttl     = "600"
  records = ["${element(aws_ses_domain_dkim.main.dkim_tokens, count.index)}.dkim.amazonses.com"]
}

resource "aws_iam_user" "smtp" {
  name = "${var.name}-smtp"
}

resource "aws_iam_user_policy" "smtp_ses_send_raw_email" {
  name = "ses-send-raw-email"
  user = "${aws_iam_user.smtp.name}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ses:SendRawEmail",
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_iam_access_key" "smtp" {
  user    = "${aws_iam_user.smtp.name}"
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

output "discourse_eip" {
  value       = "${aws_eip.discourse.public_ip}"
  description = "Discourse Elastic IP"
}

output "smtp_username" {
  value       = "${aws_iam_access_key.smtp.id}"
  description = "Amazon SES SMTP username"
}

output "smtp_password" {
  value       = "${aws_iam_access_key.smtp.ses_smtp_password}"
  description = "Amazon SES SMTP password"
}
