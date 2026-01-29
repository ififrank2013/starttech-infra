#!/bin/bash

echo "Deleting all versions..."
aws s3api list-object-versions --bucket prod-frontend-197104194412 --query 'Versions[].[Key,VersionId]' --output text | while read key versionid; do
  echo "Deleting: $key VersionId: $versionid"
  aws s3api delete-object --bucket prod-frontend-197104194412 --key "$key" --version-id "$versionid"
done

echo "Deleting delete markers..."
aws s3api list-object-versions --bucket prod-frontend-197104194412 --query 'DeleteMarkers[].[Key,VersionId]' --output text | while read key versionid; do
  echo "Deleting marker: $key VersionId: $versionid"
  aws s3api delete-object --bucket prod-frontend-197104194412 --key "$key" --version-id "$versionid"
done

echo "Deleting bucket..."
aws s3api delete-bucket --bucket prod-frontend-197104194412 --region us-east-1
echo "Bucket deleted!"
