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

resource "aws_alb_target_group" "${var.backend_port[count.index]}" {
  count    = "${length(var.backend_port)}"
  name     = "${var.alb_name}-tg"
  port     = "${var.backend_port[count.index]}"
  protocol = "${upper(var.backend_protocol)}"
  vpc_id   = "${var.vpc_id}"

  health_check {
    interval            = 30
    path                = "${var.health_check_path}"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    protocol            = "${var.backend_protocol}"
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = "${var.cookie_duration}"
    enabled         = "${ var.cookie_duration == 1 ? false : true}"
  }

  tags = "${merge(var.tags, map("Name", format("%s-tg", var.alb_name)))}"
}

resource "aws_alb_listener" "front_end_http" {
  load_balancer_arn = "${aws_alb.main.arn}"
  port              = "${var.backend_port[count.index]}"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.var.backend_port[count.index].id}"
    type             = "forward"
  }

  # should be 0 if no HTTP, otherwise length of var.backend_port
  count = "${trimspace(element(split(",", var.alb_protocols), 1)) == "HTTP" || trimspace(element(split(",", var.alb_protocols), 2)) == "HTTP" ? length(var.backend_port) : 0}"
}

resource "aws_alb_listener" "front_end_https" {
  load_balancer_arn = "${aws_alb.main.arn}"
  port              = "${var.backend_port[count.index]}"
  protocol          = "HTTPS"
  certificate_arn   = "${var.certificate_arn}"
  ssl_policy        = "ELBSecurityPolicy-2015-05"

  default_action {
    target_group_arn = "${aws_alb_target_group.var.backend_port[count.index].id}"
    type             = "forward"
  }
  # should be 0 if no HTTPS, otherwise length of var.backend_port
  count = "${trimspace(element(split(",", var.alb_protocols), 1)) == "HTTPS" || trimspace(element(split(",", var.alb_protocols), 2)) == "HTTPS" ? length(var.backend_port) : 0}"
}
