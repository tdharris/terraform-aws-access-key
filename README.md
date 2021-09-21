# Manage AWS IAM Access Keys
Create, delete, rotate AWS IAM Access Keys with Terraform. Secret is encrypted and decrypted with `pgp_key` (keybase).

## Install
TODO

### Dependencies
Ensure that [keybase cli](https://keybase.io/docs/the_app/install_linux) is installed and you are logged in. Verify username with:
```console
keybase whoami
```

## Usage
AWS Access Key is managed by terraform. Simply destroy and apply to rotate. Use [terraform workspaces](https://www.terraform.io/docs/language/state/workspaces.html) for managing multiple keys.

### Setup a new key
Create a new AWS Key to be managed by terraform.
- Create a `terraform.tfvars` file (see [Security](#security) for more info):
    ```tfvar
    pgp_key = "keybase:some_person_that_exists"
    ```
- (*optional*) Create a Terraform Workspace:
    
    **Note** : Each key is managed with a different workspace to separate state files. If not using the `default` workspace, create a new one or select an existing one.
    ```console
    terraform workspace new <name>
    ```

- Ensure the current `AWS Caller Identity` is the account you intend to manage in this workspace:
 
    **Note** : This identity is used by terraform invocations.
    ```console
    aws sts get-caller-identity
    ```

- Create a new key:

    **Note** : This helper script will run `terraform apply`, then decrypt the output with keybase.
    ```console
    ./aws-key.sh create
    ```

### Rotate a key
Rotate an existing AWS Key that is already being managed by terraform.
- Select the appropriate Terraform Workspace:

    **Note** : Each key is managed with a different workspace to separate state files. If not using the `default` workspace, create a new one or select an existing one.
    ```console
    terraform workspace select <name>
    ```

- Ensure the current `AWS Caller Identity` is the account you intend to manage in the selected workspace:
 
    **Note** : This identity is used by terraform invocations.
    ```console
    aws sts get-caller-identity
    ```

- Rotate the existing key:

    **Note** : This helper script will run `terraform destroy`, `terraform apply`, then decrypt the output with keybase.
    ```console
    ./aws-key.sh rotate
    ```

### Decrypt a key
Decrypt an existing AWS Key that is already being managed by terraform.

- Select the appropriate Terraform Workspace:

    **Note** : Each key is managed with a different workspace to separate state files. If not using the `default` workspace, create a new one or select an existing one.
    ```console
    terraform workspace select <name>
    ```

- Decrypt the existing key:

    **Note** : This helper script will get the key's `encrypted_secret` from terraform state, then decrypt with keybase.
    ```console
    ./aws-key.sh decrypt
    ```

## Sample Output
### Rotate a key
- Select the workspace
    ```console
    teraform workspace select default
    ```
- Rotate the key
    ```shell
    $ ./rotate-aws-key.sh 
    Previously invoked identity (tfstate):
    {
    "account_id" = "<account-id>"
    "arn" = "arn:aws:iam::<account-id>:user/mycli"
    "id" = "<account-id>"
    "user_id" = "<user-id>"
    }
    Current AWS Identity: 
    {
        "UserId": "<user-id>",
        "Account": "<account-id>",
        "Arn": "arn:aws:iam::<account-id>:user/mycli"
    }
    Validating tfstate identity is the same as current aws identity...
    ✔ Success

    Rotate aws access key '<old-access-key-id>' ? [y/n] y
    Rotating access key with terraform destroy, then apply...
    ```
    ```hcl
    aws_iam_access_key.example: Refreshing state... [id=<old-access-key-id>]

    Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
    - destroy

    Terraform will perform the following actions:

    # aws_iam_access_key.example will be destroyed
    - resource "aws_iam_access_key" "example" {
        - create_date          = "<date>" -> null
        - encrypted_secret     = "<secret>" -> null
        - id                   = "<old-access-key-id>" -> null
        - key_fingerprint      = "<fingerprint>" -> null
        - pgp_key              = "keybase:some_person_that_exists" -> null
        - ses_smtp_password_v4 = (sensitive value)
        - status               = "Active" -> null
        - user                 = "mycli" -> null
        }

    Plan: 0 to add, 0 to change, 1 to destroy.

    Changes to Outputs:
    - aws_access_key_id   = "<old-access-key-id>" -> null
    - aws_caller_identity = {
        - account_id = "<account-id>"
        - arn        = "arn:aws:iam::<account-id>:user/mycli"
        - id         = "<account-id>"
        - user_id    = "<user-id>"
        } -> null
    - aws_user_name       = "mycli" -> null
    - encrypted_secret    = (sensitive value)
    aws_iam_access_key.example: Destroying... [id=<old-access-key-id>]
    aws_iam_access_key.example: Destruction complete after 0s

    Destroy complete! Resources: 1 destroyed.
    ```
    ```hcl
    Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:       
    + create

    Terraform will perform the following actions:

    # aws_iam_access_key.example will be created
    + resource "aws_iam_access_key" "example" {
        + create_date          = (known after apply)
        + encrypted_secret     = (known after apply)
        + id                   = (known after apply)
        + key_fingerprint      = (known after apply)
        + pgp_key              = "keybase:some_person_that_exists"
        + secret               = (sensitive value)
        + ses_smtp_password_v4 = (sensitive value)
        + status               = "Active"
        + user                 = "mycli"
        }

    Plan: 1 to add, 0 to change, 0 to destroy.

    Changes to Outputs:
    + aws_access_key_id   = (known after apply)
    + aws_caller_identity = {
        + account_id = "<account-id>"
        + arn        = "arn:aws:iam::<account-id>:user/mycli"
        + id         = "<account-id>"
        + user_id    = "<user-id>"
        }
    + aws_user_name       = "mycli"
    + encrypted_secret    = (sensitive value)
    aws_iam_access_key.example: Creating...
    aws_iam_access_key.example: Creation complete after 1s [id=<new-access-key-id>]

    Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
    
    Outputs:

    aws_access_key_id = "<new-access-key-id>"
    aws_caller_identity = {
    "account_id" = "<account-id>"
    "arn" = "arn:aws:iam::<account-id>:user/mycli"
    "id" = "<account-id>"
    "user_id" = "<user-id>"
    }
    aws_user_name = "mycli"
    encrypted_secret = <sensitive>
    ```
    ```shell
    Decrypted Outputs:

    aws_user_name = "mycli"
    aws_access_key_id = "<new-access-key-id>"
    aws_decrypted_secret = "<decrypted-secret>"
    ```
- Update my key and show it was successful:
    ```shell
    # Update bitwarden with my new key id and secret
    # Then sync bw cli as this is how I source by aws keys
    $ bw sync
    Syncing complete.
    $ envaws-personal
    $ awsme
    {
        "UserId": "<user-id>",
        "Account": "<account-id>",
        "Arn": "arn:aws:iam::<account-id>:user/mycli"
    }
    $ printenv | grep 'AWS_ACCESS_KEY_ID'
    AWS_ACCESS_KEY_ID=<new-access-key-id>
    ```

## Security
To avoid storing the secret in plaintext in `tfstate`, the secret is encrypted with a [pgp_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_access_key#pgp_key):
> Either a base-64 encoded PGP public key, or a keybase username in the form `keybase:some_person_that_exists`, for use in the `encrypted_secret` output attribute.
