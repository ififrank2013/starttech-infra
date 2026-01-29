import boto3

s3 = boto3.client('s3', region_name='us-east-1')
bucket = 'prod-frontend-197104194412'

paginator = s3.get_paginator('list_object_versions')
for page in paginator.paginate(Bucket=bucket):
    versions = page.get('Versions', [])
    delete_markers = page.get('DeleteMarkers', [])
    
    for v in versions:
        s3.delete_object(Bucket=bucket, Key=v['Key'], VersionId=v['VersionId'])
        print(f"Deleted version: {v['Key']} ({v['VersionId']})")
    
    for dm in delete_markers:
        s3.delete_object(Bucket=bucket, Key=dm['Key'], VersionId=dm['VersionId'])
        print(f"Deleted marker: {dm['Key']} ({dm['VersionId']})")

print("All versions deleted")

# Now delete the bucket
s3.delete_bucket(Bucket=bucket)
print(f"Deleted bucket {bucket}")
