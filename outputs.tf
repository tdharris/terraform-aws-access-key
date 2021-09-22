
output "aws_caller_identity" {
  value = data.aws_caller_identity.current
}

output "aws_user_name" {
  value = local.aws_user_name
}

output "encrypted_secret" {
  value     = aws_iam_access_key.key.encrypted_secret
  sensitive = true
}

output "aws_access_key_id" {
  value = aws_iam_access_key.key.id
}

# output "decrypted_secret" {
#   values = data.external.external_keybase_decrypt
# }
