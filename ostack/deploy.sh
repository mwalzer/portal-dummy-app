#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
# (but allow for the error trap)
set -eE

# keys exists at $PUBLIC_KEY, $PRIVATE_KEY and profile key at $ssh_key
export TF_VAR_public_key_path=$PUBLIC_KEY

eval $(ssh-agent -s)
ssh-add $PRIVATE_KEY

echo Setting up Terraform creds && \
  export TF_VAR_username=${OS_USERNAME} && \
  export TF_VAR_password=${OS_PASSWORD} && \
  export TF_VAR_tenant=${OS_TENANT_NAME} && \
  export TF_VAR_auth_url=${OS_AUTH_URL}

# make sure image is available in openstack
#ansible-playbook "$PORTAL_APP_REPO_FOLDER/playbooks/import-openstack-image.yml"
#ansible-playbook "$PORTAL_APP_REPO_FOLDER/playbooks/import-openstack-image.yml" \
#	-e img_version="current" \
#        -e img_prefix="Ubuntu-16.04" \
#	-e url_prefix="http://cloud-images.ubuntu.com/xenial/" \
#	-e url_suffix="xenial-server-cloudimg-amd64-disk1.img" \
#	-e compress_suffix=""

if [ -n ${K8S_MASTER_GX_PORT+x} ]; then echo "var is set"; fi

export KARGO_TERRAFORM_FOLDER=$PORTAL_APP_REPO_FOLDER'/kubespray/contrib/terraform/openstack'

cd $PORTAL_APP_REPO_FOLDER'/kubespray'
terraform apply --state=$PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/terraform.tfstate' $KARGO_TERRAFORM_FOLDER

cp contrib/terraform/terraform.py $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/hosts'
cp -r inventory/group_vars $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/'
# $PORTAL_DEPLOYMENT_REFERENCE is set by portal and makes it unique per deployments

# Provision kubespray
ansible-playbook --flush-cache -b --become-user=root -i $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/hosts' cluster.yml \
	--key-file "$PRIVATE_KEY" \
	-e bootstrap_os=ubuntu \
	-e host_key_checking=false \
	-e cloud_provider="openstack" \
	-e efk_enabled=false \
	-e kubelet_deployment_type=$KUBELET_DEPLOYMENT_TYPE \
	-e kube_api_pwd=$TF_VAR_kube_api_pwd \
	-e cluster_name=$TF_VAR_cluster_name \
	-e helm_enabled=true \
	-e kube_version=$KUBE_VERSION \
	-e kube_network_plugin="weave"


# Provision glusterfs
ansible-playbook -b --become-user=root -i $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/hosts' \
	./contrib/network-storage/glusterfs/glusterfs.yml \
	--key-file "$PRIVATE_KEY" \
	-e host_key_checking=false \
	-e bootstrap_os=ubuntu

# Set permissive access control and add '30700 open' security group
ansible-playbook -b --become-user=root -i $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/hosts' \
	../extra-playbooks/rbac/rbac.yml \
	--key-file "$PRIVATE_KEY"

# Start Galaxy, provision galaxy dataset, start workflow
ansible-playbook -b --become-user=root -i $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/hosts' \
	../extra-playbooks/k8s-galaxy/k8s-galaxy.yml \
	--key-file "$PRIVATE_KEY"
#  --write_to_/opt/galaxy_data/test.txt

# wait for write_to_/opt/galaxy_data/test.txt and write to local file
ansible-playbook -b --become-user=root -i $PORTAL_DEPLOYMENTS_ROOT'/'$PORTAL_DEPLOYMENT_REFERENCE'/hosts' \
	../extra-playbooks/get-results/get-results.yml \
	--key-file "$PRIVATE_KEY" \

helm_test_param=`cat helm_test_param.txt`
