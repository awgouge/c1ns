import json
import boto3
import os


def nsva_ha_event(event, context):
    """NSVA HA Lambda entrypoint"""
    print(f"Event: {event}")
    if os.environ['FAILOVER'] == "true":
        failover = True
    else:
        failover = False
    if 'bypass' in event:
        # Lambda triggered manually via a 'test event' to bypass/unbypass
        # - If bypassing, disable the Lambda, else enable the Lambda
        lambda_enable(not event['bypass'])
        all_nsva_bypass(event['bypass'])
    elif is_lambda_enabled():
        # Lambda triggered by NSVA CloudWatch Alarm via SNS
        instance_id, alarm_state = parse_sns_event(event)
        if alarm_state == "OK":
            nsva_bypass(instance_id, False, failover)
        elif alarm_state == "ALARM":
            nsva_bypass(instance_id, True, failover)
        else:
            print(f"Invalid Alarm state {alarm_state} for {instance_id}")


def lambda_enable(enable):
    """Enables or Disables this Lambda"""
    ssm = boto3.client('ssm')
    if enable:
        print("Enabling Lambda")
        ssm.put_parameter(Name="/nsva/ha_lambda_enabled", Value="true", Overwrite=True)
    else:
        print("Disabling Lambda")
        ssm.put_parameter(Name="/nsva/ha_lambda_enabled", Value="false", Overwrite=True)


def is_lambda_enabled():
    """Return if this Lambda is enabled"""
    ssm = boto3.client('ssm')
    ssm_param = ssm.get_parameter(Name="/nsva/ha_lambda_enabled")
    ha_lambda_enabled = ssm_param['Parameter']['Value'] == "true"
    print(f"Lambda Enabled: {ha_lambda_enabled}")
    return ha_lambda_enabled


def all_nsva_bypass(bypass):
    """Bypass or Unbypass all NSVAs"""
    ec2 = boto3.client("ec2")
    inspection_vpc_id = ec2.describe_vpcs(Filters=[{'Name': 'tag:Name', 'Values': ['inspection-vpc']}])['Vpcs'][0]['VpcId']
    instances = ec2.describe_instances(Filters=[{'Name': 'network-interface.vpc-id', 'Values': [inspection_vpc_id]}])

    for instance in instances["Reservations"]:
        nsva_bypass(instance["Instances"][0]['InstanceId'], bypass, True) #when bypassing all, only bypass


def nsva_bypass(instance_id, bypass, failover):
    """Bypass or Unbypass the specified NSVA"""

    # Get the NSVA Availability Zone AZ
    ec2 = boto3.client("ec2")
    instance = ec2.describe_instances(InstanceIds=[instance_id])
    try:
        azone = instance["Reservations"][0]["Instances"][0]["Placement"]["AvailabilityZone"]
    except Exception:
        print("ERROR: Could not query the NSVA AZ")
        return

    # Get information about the bypass and unbypass Route Tables
    unbypass_rtb_name = 'inspection-unbypass-connection-route-table-' + azone
    unbypass_rtb = ec2.describe_route_tables(Filters=[{'Name': 'tag:Name', 'Values': [unbypass_rtb_name]}])
    if failover:
        bypass_rtb_name = 'inspection-failover-connection-route-table-' + azone
    else:
        bypass_rtb_name = 'inspection-bypass-connection-route-table-' + azone
    bypass_rtb = ec2.describe_route_tables(Filters=[{'Name': 'tag:Name', 'Values': [bypass_rtb_name]}])

    # Find the Connection Subnet Route Table Association ID (either the bypass/unbypass Route Table will be associated)
    if unbypass_rtb["RouteTables"][0]["Associations"]:
        rtb_association_id = unbypass_rtb["RouteTables"][0]["Associations"][0]["RouteTableAssociationId"]
    elif bypass_rtb["RouteTables"][0]["Associations"]:
        rtb_association_id = bypass_rtb["RouteTables"][0]["Associations"][0]["RouteTableAssociationId"]
    else:
        print("ERROR: Could not find Route Table Association")
        return

    # Bypass/Unbypass as requested
    if bypass:
        rtb_id = bypass_rtb["RouteTables"][0]["RouteTableId"]
        ec2.replace_route_table_association(AssociationId=rtb_association_id, RouteTableId=rtb_id)
        print(f"Bypassed NSVA {instance_id} {azone} using {bypass_rtb_name}")
    else:
        rtb_id = unbypass_rtb["RouteTables"][0]["RouteTableId"]
        ec2.replace_route_table_association(AssociationId=rtb_association_id, RouteTableId=rtb_id)
        print(f"Unbypassed NSVA {instance_id} {azone}")


def parse_sns_event(event):
    """Parse SNS event"""
    message = json.loads(event["Records"][0]["Sns"]["Message"])
    alarm_state = message["NewStateValue"]
    instance_id = None
    for dim in message["Trigger"]["Dimensions"]:
        if dim["name"] == "InstanceId":
            instance_id = dim["value"]
            break
    if instance_id is None:
        raise AttributeError("ERROR: Could not find Instance ID")
    return instance_id, alarm_state
