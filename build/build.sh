# git commits
echo "GIT_COMMIT = ${GIT_COMMIT}"
echo "GIT_PREVIOUS_SUCCESSFUL_COMMIT = ${GIT_PREVIOUS_SUCCESSFUL_COMMIT}"

currGitCommit=${GIT_COMMIT}
prevGitCommit=${GIT_PREVIOUS_SUCCESSFUL_COMMIT}

if [ -z $2 ]; then
    echo "no commit id override"
else 
    echo "prev commit id override: $2"
    prevGitCommit=$2
fi    

echo "currGitCommit = $currGitCommit"
echo "prevGitCommit = $prevGitCommit"

# if previous commit id is null
if $1 && [ -z $prevGitCommit ]; then
    echo "cannot run incremental deployment with null prevGitCommit"
    exit 1
fi 

# if current and previous git commits are same
if $1 && [[ $currGitCommit == $prevGitCommit ]]; then
    echo "current and previous git cimmits are same, no change to deploy"
    exit 0
fi   

# list of files modifed
echo "***************list of modified files***************"
git diff --name-only $currGitCommit $prevGitCommit

tempDirectory="temp-dir"
deploymentPath="salesforce_sfdx"
changeDetected=false

echo "***************building salesforce_sfdx folder***************"

# loop through list of modified files
git diff -z --name-only $currGitCommit $prevGitCommit|
while read -d $'\0' fileName
do
    echo "current file : $fileName"
        
        # if file modified file is from salesforce_sfdx/main/default
        if [[ $fileName == *"salesforce_sfdx"* ]]; then
            echo "including $fileName"
            
            changeDetected=true           
            
            # First create the target directory, if it doesn't exist
            directoryName=$(dirname "$fileName")
            mkdir -p "$tempDirectory/$directoryName"
            
            # Then copy over the file
            cp -rf "$fileName" "$tempDirectory/$fileName"
            
            # Then copy over the meta data file if it exists
            metaFileName="$fileName-meta.xml"
            if [ -f "$metaFileName" ]; then
                echo "including $metaFileName"
                cp -rf "$metaFileName" "$tempDirectory/$metaFileName"
            fi    
        else 
            echo "skipped $fileName"
        fi
done
    
# navigate to workspace
cd $WORKSPACE

# if incremental deployment
if $1; then
    echo "***************incremental changes***************"
    # if no file changed
    if [ ! -d "$tempDirectory" ]; then
        echo "no change detected, exiting"
        exit 0
    fi    

    # rename force-app folder
    mv salesforce_sfdx salesforce_sfdx-old

    # copy force-app folder from temp directory to workspace
    cp -r $tempDirectory/salesforce_sfdx $WORKSPACE
fi

# verify salesforce_sfdx folder, components from salesforce_sfdx folder will be deployed
echo "***************Deployment folder***************"
cd $deploymentPath
ls

# navigate to workspace
cd $WORKSPACE

# deploy force-app using sfdx
# reference https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference_force_source.htm
echo "***************Salesforce CLI***************"
sfdx --version
sfdx force:auth:logout -u $userName -p
sfdx force:auth:jwt:grant --clientid $clientId --jwtkeyfile $secretFile --username $userName --instanceurl $serverUrl

if [[ $target == *"validate"* ]]; then
    sfdx force:source:deploy -l $testLevel -u $userName -p $deploymentPath -c 
else
    sfdx force:source:deploy -l $testLevel -u $userName -p $deploymentPath
    vlocity -sfdx.username $userName -job jobs/deploy.yaml packDeploy --verbose true --simpleLogging true
fi




: '
echo "####### Login"
sfdx force:auth:logout -u $userName -p
sfdx force:auth:jwt:grant --clientid $clientId --jwtkeyfile $secretFile --username $userName --instanceurl $serverUrl

echo "####### Create SF Delta Package"
sfdx plugins:install vlocityestools
if [ -d salesforce_sfdx_delta ]; then
    rm -rf salesforce_sfdx_delta  
fi
sfdx vlocityestools:sfsource:createdeltapackage -u $userName -p ins -d salesforce_sfdx


if [ -d salesforce_sfdx_delta ]; then
    echo "####### force:source:deploy"
    sfdx force:source:deploy -l $testLevel -u $userName -p salesforce_sfdx_delta
else
    echo "### NO SF DELTA-FOLDER FOUND"
fi

echo "####### packDeploy"
vlocity -sfdx.username $userName  -job Deploy_Delta.yaml packDeploy --verbose true --simpleLogging true
echo "####### runApex"
vlocity -sfdx.username $userName --nojob runApex -apex apex/RunProductBatchJobs.cls --verbose true --simpleLogging true
'
