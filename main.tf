
data "aws_caller_identity" "current" {}

locals {
  # Get 'friendly' 'user_name'
  aws_user_arn  = lookup(data.aws_caller_identity.current, "arn", null)
  aws_user_name = replace(regex("/.*$", local.aws_user_arn), "/", "")
}

# lookup user to verify parse
data "aws_iam_user" "current" {
  user_name = local.aws_user_name
}

resource "aws_iam_access_key" "key" {
  user    = local.aws_user_name
  pgp_key = var.pgp_key
}

# Decrypted secret stored in state with the approach below
# data "external" "external_keybase_decrypt" {
#   program = ["${path.module}/lib/external_keybase_decrypt.sh"]
#   query = {
#     encrypted_secret = aws_iam_access_key.key.encrypted_secret
#   }
# }
