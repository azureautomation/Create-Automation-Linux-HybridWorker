import subprocess
import os
from datetime import datetime
import time
from optparse import OptionParser

def run_command(cmd):
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = proc.communicate()
    return proc.returncode, stdout, stderr

def download_omsagent(options):
    workspaceId = options.workspace_id
    workspaceKey = options.workspace_key
    workspaceRegion = options.region

    opinsightsVal = "opinsights.azure.com"
    cmdToDownloadOmsAgent = ["wget", "https://raw.githubusercontent.com/Microsoft/OMS-Agent-for-Linux/master/installer/scripts/onboard_agent.sh"] 
    cmdToInstallOmsAgent = ["sh", "onboard_agent.sh", "-w", workspaceId, "-s", workspaceKey, "-d", opinsightsVal]
    
    returncode, _, _ = run_command(cmdToDownloadOmsAgent)
    
    if(returncode == 0):
        returncode, _, _ = run_command(cmdToInstallOmsAgent)

        if(returncode != 0):
            return False
        else:
            cmdToInvokePerformedRequiredConfigChecks = ["sudo", "su", "omsagent", "-c", "python /opt/microsoft/omsconfig/Scripts/PerformRequiredConfigurationChecks.py"]
            run_command(cmdToInvokePerformedRequiredConfigChecks)
            return True
    else:
        return False

def register_woker(options):

    workspaceId = options.workspace_id
    automationSharedKey = options.automation_account_key
    hybridGroupName = options.hybrid_worker_group_name
    automationEndpoint = options.registration_endpoint

    tries = 1
    max_tries = 5
    worker_present = False
    while(not worker_present):
        if tries > max_tries:
            break
        time_to_wait = 3 * (2 ** tries)
        if time_to_wait > 60:
            time_to_wait = 60
        time.sleep(time_to_wait)
        if(not os.path.isdir("/opt/microsoft/omsconfig/modules/nxOMSAutomationWorker/DSCResources/MSFT_nxOMSAutomationWorkerResource/automationworker")):
            print("Worker isnt downloaded yet....")
            tries += 1
        else:
            worker_present = True
            break

    if(worker_present):
        cmdToRegisterUserHW = ["sudo", "python", "/opt/microsoft/omsconfig/modules/nxOMSAutomationWorker/DSCResources/MSFT_nxOMSAutomationWorkerResource/automationworker/scripts/onboarding.py", "--register", "-w", workspaceId,"-k", automationSharedKey, "-g",hybridGroupName,"-e", automationEndpoint]

        returncode, _, stderr = run_command(cmdToRegisterUserHW)
        if(returncode == 0):
            cmdToTurnOffSignValidation = ["sudo", "python","/opt/microsoft/omsconfig/modules/nxOMSAutomationWorker/DSCResources/MSFT_nxOMSAutomationWorkerResource/automationworker/scripts/require_runbook_signature.py", "--false", workspaceId]

            returncode, _, stderr = run_command(cmdToTurnOffSignValidation)
            if(returncode != 0):
                print("Registration failed because of "+str(stderr))
                return
            print("Successfully registerd worker.")
        else:
            print("registration failed because of " + str(stderr))
    else:
        print("Worker download failing...")


def main():
    parser = OptionParser(
        usage="usage: %prog -e endpoint -k key -g groupname -w workspaceid -wk workspacekey")

    parser.add_option("-e", "--endpoint", dest="registration_endpoint", help="Agent service registration endpoint.")
    parser.add_option("-k", "--key", dest="automation_account_key", help="Automation account primary/secondary key.")
    parser.add_option("-g", "--groupname", dest="hybrid_worker_group_name", help="Hybrid worker group name.")
    parser.add_option("-w", "--workspaceid", dest="workspace_id", help="Workspace id.")
    parser.add_option("-l", "--workspacekey", dest="workspace_key", help="Workspace Key.")
    parser.add_option("-r", "--region", dest="region", help="Workspace region")

    (options, _) = parser.parse_args()
    if(download_omsagent(options)):
        register_woker(options)

if __name__ == "__main__":
    main()
