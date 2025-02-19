/*
    Normal Transfer Tool
    Author: Baish
    Description: This script transfers normals from a donor mesh to a receiver mesh in 3ds Max, 
                 even if they have different vertex counts, by finding the closest matching vertices.
    Version: 1.0
*/

macroScript NormalTransferTool
category:"Custom Scripts"
toolTip:"Normal Transfer Tool"
(
    try(destroyDialog NormalTransferTool) catch()

    rollout NormalTransferTool "Normal Transfer Tool" width:200
    (
        local donor = undefined
        local receiver = undefined

        -- Button to select donor
        button btnSelectDonor "Select Donor" width:180
        label lblDonor "Donor: Not Selected" align:#left

        -- Button to select receiver
        button btnSelectReceiver "Select Receiver" width:180
        label lblReceiver "Receiver: Not Selected" align:#left

        -- Button to start normal transfer
        button btnTransfer "Transfer Normals" width:180 enabled:false

        -- Handler for selecting donor
        on btnSelectDonor pressed do
        (
            if selection.count == 1 then
            (
                donor = selection[1]
                lblDonor.text = "Donor: " + donor.name
                if receiver != undefined then btnTransfer.enabled = true
            )
            else
            (
                messageBox "Please select one object as the donor."
            )
        )

        -- Handler for selecting receiver
        on btnSelectReceiver pressed do
        (
            if selection.count == 1 then
            (
                receiver = selection[1]
                lblReceiver.text = "Receiver: " + receiver.name
                if donor != undefined then btnTransfer.enabled = true
            )
            else
            (
                messageBox "Please select one object as the receiver."
            )
        )

        -- Handler for transferring normals
        on btnTransfer pressed do
        (
            if (classof donor != Editable_Mesh) or (classof receiver != Editable_Mesh) then
            (
                messageBox "Both objects must be Editable_Mesh."
            )
            else
            (
                for i = 1 to receiver.numverts do
                (
                    local receiverPos = getVert receiver i
                    local closestDist = 1e9
                    local closestNormal = [0,0,0]
                    
                    for j = 1 to donor.numverts do
                    (
                        local donorPos = getVert donor j
                        local dist = distance receiverPos donorPos
                        
                        if dist < closestDist then
                        (
                            closestDist = dist
                            closestNormal = getNormal donor j
                        )
                    )
                    
                    setNormal receiver i closestNormal
                )
                
                update receiver
                messageBox "Normals have been successfully transferred!"
            )
        )
    )

    -- Display UI
    createDialog NormalTransferTool
)
