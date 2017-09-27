### ALB resources

# TODO:
# support not logging

data "template_file" "bucket_policy" {
  template = "${file("${path.module}/bucket_policy.json")}"

  vars {
    log_bucket           = "${var.log_bucket}"
    log_prefix           = "${var.log_prefix}"
    account_id           = "${var.aws_account_id}"
    principle_account_id = "${lookup(var.principle_account_id, var.aws_region)}"
  }
}

resource "aws_alb" "main" {
  name            = "${var.alb_name}"
  subnets         = ["${var.subnets}"]
  security_groups = ["${var.alb_security_groups}"]
  internal        = "${var.alb_is_internal}"

  access_logs {
    bucket  = "${var.log_bucket}"
    prefix  = "${var.log_prefix}"
    enabled = "${var.log_bucket != ""}"
  }

  tags = "${merge(var.tags, map("Name", format("%s", var.alb_name)))}"
}

resource "aws_s3_bucket" "log_bucket" {
  count         = "${var.log_bucket != "" ? 1 : 0}"
  bucket        = "${var.log_bucket}"
  policy        = "${data.template_file.bucket_policy.rendered}"
  force_destroy = true

  tags = "${merge(var.tags, map("Name", format("%s", var.log_bucket)))}"
}

module "target_group_listeners" {
  source            = "./components"
  count             = "${length(var.backend_ports)}"
  backend_port      = "${var.backend_ports[count.index]}"
  backend_protocol  = "${var.backend_protocol}"
  alb_protocols     = "${var.alb_protocols}"
  alb_name          = "${var.alb_name}"
  vpc_id            = "${var.vpc_id}"
  health_check_path = "${var.health_check_path}"
  cookie_duration   = "${var.cookie_duration}"
  certificate_arn   = "${var.certificate_arn}"
  tags              = "${var.tags}"
}