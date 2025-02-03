AWS_REGION=ap-south-1
HUB_ACCOUNT_NUMBER=$(shell aws sts get-caller-identity --query "Account" --output text --profile a1)
SPOKE_ACCOUNT_A_NUMBER=$(shell aws sts get-caller-identity --query "Account" --output text --profile a2)
SPOKE_ACCOUNT_B_NUMBER=$(shell aws sts get-caller-identity --query "Account" --output text --profile a3)

terraform-init:
	cd terraform && terraform init

test:
	cd terraform && terraform plan -generate-config-out=generated.tf --profile a1

apply:
	make deploy-ram-shares
	make deploy-foundational-resources-in-hub-account	
	make deploy-route-53-resolver-endpoints-in-hub-account
	make deploy-route-53-resolver-rule-in-hub-account
	make ram-share-resolver-rule-in-hub-account
	make ram-share-route-53-resolver-with-spoke-accounts
	make deploy-transit-gateway
	make associate-private-hz-in-spoke-account-a-with-dns-vpc
	make associate-private-hz-in-spoke-account-b-with-dns-vpc
	make delete-private-hz-and-dns-vpc-association-authorization
	make deploy-foundational-resources-in-spoke-account-a
	make deploy-ecr-repo-in-spoke-account-a
	make deploy-ecs-task-in-spoke-account-a
	make deploy-foundational-resources-in-spoke-account-b
	make deploy-ecr-repo-in-spoke-account-b
	make deploy-ecs-task-in-spoke-account-b

deploy-ram-shares:
	cd terraform && terraform apply \
	-target="module.hub_account.aws_ram_resource_share.example" \
	-target="module.hub_account.aws_ram_principal_association.account_a" \
	-target="module.hub_account.aws_ram_principal_association.account_b" \
	-target="module.spoke_account_a.aws_ram_resource_share_accepter.spoke_account_a_receiver_accept" \
	-target="module.spoke_account_b.aws_ram_resource_share_accepter.spoke_account_b_receiver_accept" \
	--auto-approve

deploy-foundational-resources-in-hub-account:
	cd terraform && terraform apply \
	-target="module.hub_account.aws_vpc.dns_vpc" \
	-target="module.hub_account.aws_subnet.private_subnet_1" \
	-target="module.hub_account.aws_subnet.private_subnet_2" \
	-target="module.hub_account.aws_security_group.allow_all_traffic" \
	--auto-approve

deploy-route-53-resolver-endpoints-in-hub-account:
	cd terraform && terraform apply \
	-target="module.hub_account.aws_route53_resolver_endpoint.outbound" \
	-target="module.hub_account.aws_route53_resolver_endpoint.inbound" \
	--auto-approve

deploy-route-53-resolver-rule-in-hub-account:
	cd terraform && terraform apply \
	-target="module.hub_account.aws_route53_resolver_rule.example" \
	--auto-approve

ram-share-resolver-rule-in-hub-account:
	cd terraform && terraform apply \
	-target="module.hub_account.aws_ram_resource_association.resolver_rule" \
	--auto-approve

ram-share-route-53-resolver-with-spoke-accounts:
	cd terraform && terraform apply \
	-target="module.spoke_account_a.aws_route53_resolver_rule.example_local" \
	-target="module.spoke_account_a.aws_route53_resolver_rule_association.resolver_rule_vpc_assocation_in_spoke_account_a" \
	--auto-approve

associate-private-hz-in-spoke-account-a-with-dns-vpc:
	cd terraform && terraform apply \
	-target="module.spoke_account_a.aws_route53_vpc_association_authorization.private_hz_in_spoke_account_a_dns_vpc_in_hub_account_association_authorization" \
	-target="module.hub_account.aws_route53_zone_association.private_hz_in_spoke_account_a_dns_vpc_in_hub_account_association" \
	--auto-approve

associate-private-hz-in-spoke-account-b-with-dns-vpc:
	cd terraform && terraform apply \
	-target="module.spoke_account_b.aws_route53_vpc_association_authorization.private_hz_in_spoke_account_b_dns_vpc_in_hub_account_association_authorization" \
	-target="module.hub_account.aws_route53_zone_association.private_hz_in_spoke_account_b_dns_vpc_in_hub_account_association" \
	--auto-approve

delete-private-hz-and-dns-vpc-association-authorization:
	cd terraform && terraform destroy \
	-target="module.spoke_account_a.aws_route53_vpc_association_authorization.private_hz_in_spoke_account_a_dns_vpc_in_hub_account_association_authorization" \
	-target="module.spoke_account_b.aws_route53_vpc_association_authorization.private_hz_in_spoke_account_b_dns_vpc_in_hub_account_association_authorization" \
	--auto-approve

deploy-foundational-resources-in-spoke-account-a:
	cd terraform && terraform apply \
	-target="module.spoke_account_a.aws_vpc.my_vpc" \
	-target="module.spoke_account_a.aws_subnet.public_subnet" \
	-target="module.spoke_account_a.aws_internet_gateway.my_igw" \
	-target="module.spoke_account_a.aws_route_table.public_route_table" \
	-target="module.spoke_account_a.aws_route_table_association.aws_route_table_association" \
	-target="module.spoke_account_a.aws_security_group.allow_all_traffic" \
	--auto-approve

deploy-private-dns-namespace-in-spoke-account-a:
	cd terraform && terraform apply \
	-target="module.spoke_account_a.aws_service_discovery_private_dns_namespace.acc2_example_local" \
	--auto-approve

deploy-ecr-repo-in-spoke-account-a:
	cd terraform && terraform apply \
	-target="module.spoke_account_a.aws_ecr_repository.service_a_ecr_repository" \
	--auto-approve
	aws ecr get-login-password --region ${AWS_REGION} --profile a2 | docker login --username AWS --password-stdin ${SPOKE_ACCOUNT_A_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com
	docker build -t service_a_ecr_repository app/ServiceA
	docker tag service_a_ecr_repository:latest ${SPOKE_ACCOUNT_A_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com/service_a_ecr_repository:latest
	docker push ${SPOKE_ACCOUNT_A_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com/service_a_ecr_repository:latest

deploy-ecs-task-in-spoke-account-a:
	cd terraform && terraform apply \
	-target="module.spoke_account_a.aws_ecs_cluster.example" \
	-target="module.spoke_account_a.aws_iam_role.ECSTaskRole" \
	-target="module.spoke_account_a.aws_iam_policy.ECSTaskRolePermissionsPolicy" \
	-target="module.spoke_account_a.aws_iam_role_policy_attachment.ecs-task-role-customer-permission-policy-attachment" \
	-target="module.spoke_account_a.aws_iam_role_policy_attachment.ecs-task-role-AWSAppMeshEnvoyAccess-managed-policy-attachment" \
	-target="module.spoke_account_a.aws_iam_role.ECSTaskExecutionRole" \
	-target="module.spoke_account_a.aws_iam_policy.ECSTaskExecutionRolePermissionsPolicy" \
	-target="module.spoke_account_a.aws_iam_role_policy_attachment.ecs-task-execution-role-customer-permission-policy-attachment" \
	-target="module.spoke_account_a.aws_iam_role_policy_attachment.ecs-task-role-AmazonECSTaskExecutionRolePolicy-managed-policy-attachment" \
	-target="module.spoke_account_a.aws_ecs_task_definition.ecs_service" \
	-target="module.spoke_account_a.aws_ecs_service.servicea" \
	-target="module.spoke_account_a.aws_service_discovery_service.example" \
	--auto-approve

deploy-foundational-resources-in-spoke-account-b:
	cd terraform && terraform apply \
	-target="module.spoke_account_b.aws_vpc.my_vpc" \
	-target="module.spoke_account_b.aws_subnet.public_subnet" \
	-target="module.spoke_account_b.aws_internet_gateway.my_igw" \
	-target="module.spoke_account_b.aws_route_table.public_route_table" \
	-target="module.spoke_account_b.aws_route_table_association.aws_route_table_association" \
	-target="module.spoke_account_b.aws_security_group.allow_all_traffic" \
	--auto-approve

deploy-private-dns-namespace-in-spoke-account-b:
	cd terraform && terraform apply \
	-target="module.spoke_account_b.aws_service_discovery_private_dns_namespace.acc3_example_local" \
	--auto-approve

deploy-ecr-repo-in-spoke-account-b:
	cd terraform && terraform apply \
	-target="module.spoke_account_b.aws_ecr_repository.service_b_ecr_repository" \
	--auto-approve
	aws ecr get-login-password --region ${AWS_REGION} --profile a3 | docker login --username AWS --password-stdin ${SPOKE_ACCOUNT_B_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com
	docker build -t service_b_ecr_repository app/ServiceB
	docker tag service_b_ecr_repository:latest ${SPOKE_ACCOUNT_B_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com/service_b_ecr_repository:latest
	docker push ${SPOKE_ACCOUNT_B_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com/service_b_ecr_repository:latest

deploy-ecs-task-in-spoke-account-b:
	cd terraform && terraform apply \
	-target="module.spoke_account_b.aws_ecs_cluster.example" \
	-target="module.spoke_account_b.aws_iam_role.ECSTaskRole" \
	-target="module.spoke_account_b.aws_iam_policy.ECSTaskRolePermissionsPolicy" \
	-target="module.spoke_account_b.aws_iam_role_policy_attachment.ecs-task-role-customer-permission-policy-attachment" \
	-target="module.spoke_account_b.aws_iam_role_policy_attachment.ecs-task-role-AWSAppMeshEnvoyAccess-managed-policy-attachment" \
	-target="module.spoke_account_b.aws_iam_role.ECSTaskExecutionRole" \
	-target="module.spoke_account_b.aws_iam_policy.ECSTaskExecutionRolePermissionsPolicy" \
	-target="module.spoke_account_b.aws_iam_role_policy_attachment.ecs-task-execution-role-customer-permission-policy-attachment" \
	-target="module.spoke_account_b.aws_iam_role_policy_attachment.ecs-task-role-AmazonECSTaskExecutionRolePolicy-managed-policy-attachment" \
	-target="module.spoke_account_b.aws_ecs_task_definition.ecs_service" \
	-target="module.spoke_account_b.aws_ecs_service.serviceb" \
	-target="module.spoke_account_b.aws_service_discovery_service.example" \
	--auto-approve

deploy-transit-gateway:
	cd terraform && terraform apply \
	-target="module.hub_account.aws_ec2_transit_gateway.example" \
	-target="module.hub_account.aws_ram_resource_association.share_tgw" \
	--auto-approve

destroy:
	aws ecr batch-delete-image --repository-name service_a_ecr_repository --image-ids imageTag=latest --profile a2
	aws ecr batch-delete-image --repository-name service_b_ecr_repository --image-ids imageTag=latest --profile a3
	cd terraform && terraform destroy \
	--auto-approve

list:
	cd terraform/ && terraform state list

# make terraform-init

