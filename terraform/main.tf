data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  common_tags = merge(
    {
      Project   = "unicorn-gameday"
      Purpose   = "wsc2022-tp53-day2-starter-kit"
      ManagedBy = "terraform"
    },
    var.tags
  )
}
