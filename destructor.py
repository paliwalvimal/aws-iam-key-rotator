import boto3
import os
import logging
import concurrent.futures

from botocore.exceptions import ClientError

IAM_KEY_ROTATOR_TABLE = os.environ.get('IAM_KEY_ROTATOR_TABLE')
RETRY_AFTER_MINS = os.environ.get('RETRY_AFTER_MINS', 5)

# AWS_REGION is by default available within lambda environment
iam = boto3.client('iam', region_name=os.environ.get('AWS_REGION'))
ses = boto3.client('ses', region_name=os.environ.get('AWS_REGION'))
dynamodb = boto3.client('dynamodb', region_name=os.environ.get('AWS_REGION'))

logger = logging.getLogger('destructor')
logger.setLevel(logging.INFO)

def send_email(email, userName, accessKey):
    logger.info('Sending mail to {} ({}) about key {} deletion'.format(userName, email, accessKey))
    try:
        ses.send_email(
            Source='FME Alert<noreply@fullmeasure.io>',
            Destination={
                'ToAddresses': [
                    email
                ]
            },
            Message={
                'Subject': {
                    'Data': 'Old Access Key Pair Deleted'
                },
                'Body': {
                    'Html': {
                        'Data': '<html><head><title>{}</title></head><body>Hey &#x1F44B; {},<br/><br/>An existing access key pair has been deleted because it reached End-Of-Life. <br/><br/>Access Key: <strong>{}</strong><br/><br/>Thanks,<br/>Team FME</body></html>'.format('Old Access Key Pair Deleted', userName, accessKey),
                        'Charset': 'UTF-8'
                    }
                }
            }
        )
        logger.info('Mail sent to {} ({})'.format(userName, email))
    except (Exception, ClientError) as ce:
        logger.error('Failed to send mail to user {} ({}). Reason: {}'.format(userName, email, ce))

def destroy_user_key(rec):
    if rec['eventName'] == 'REMOVE':
        key = rec['dynamodb']['OldImage']
        try:
            logger.info('Deleting key {}'.format(key['ak']['S']))
            iam.delete_access_key(
                UserName=key['user']['S'],
                AccessKeyId=key['ak']['S']
            )
            logger.info('Key {} and its entry deleted'.format(key['ak']['S']))

            # Send mail to user about key deletion
            send_email(key['email']['S'], key['user']['S'], key['ak']['S'])
        except (Exception, ClientError) as ce:
            logger.error('Failed to delete key/entry {}. Reason: {}'.format(key['ak']['S'], ce))
            logger.info('Adding key {} back to database'.format(key['ak']['S']))
            dynamodb.put_item(
                TableName=IAM_KEY_ROTATOR_TABLE,
                Key={
                    'user': {
                        'S': key['user']['S']
                    },
                    'ak': {
                        'S': key['ak']['S']
                    },
                    'email': {
                        'S': key['email']['S']
                    },
                    'delete_on': {
                        'N': str(int(key['delete_on']['N']) + (RETRY_AFTER_MINS * 60))
                    }
                }
            )
    else:
        logger.info('Not a delete event')

def destroy_user_keys(records):
    with concurrent.futures.ThreadPoolExecutor() as executor:
        [executor.submit(destroy_user_key(rec)) for rec in records]

def handler(event, context):
    destroy_user_keys(event['Records'])
