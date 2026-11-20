import { CloudFormationClient, DescribeStacksCommand } from "@aws-sdk/client-cloudformation";

/** Reads the CfnOutputs of a stack using the current AWS profile. */
export async function stackOutputs(stackName: string, region = "us-east-1") {
  const cfn = new CloudFormationClient({ region });
  const { Stacks } = await cfn.send(new DescribeStacksCommand({ StackName: stackName }));
  return Object.fromEntries((Stacks?.[0]?.Outputs ?? []).map((o) => [o.OutputKey!, o.OutputValue!]));
}
