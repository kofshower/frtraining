from pxr import Usd, Sdf

def convert_glb_to_usdz(glb_path, usdz_path):
    """
    Converts a GLB file to a USDZ file.
    """
    try:
        # Create a new stage for the USDZ file
        stage = Usd.Stage.CreateNew(usdz_path)
        
        # Get the root layer of the stage
        root_layer = stage.GetRootLayer()
        
        # Add a reference to the GLB file
        root_layer.subLayerPaths.append(glb_path)
        
        # Save the stage
        stage.Save()
        
        print(f"Successfully converted {glb_path} to {usdz_path}")
        
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    # Define the input and output file paths
    glb_file = "/Users/bytedance/Documents/fricu/Sources/FricuApp/Resources/shiba_inu.glb"
    usdz_file = "/Users/bytedance/Documents/fricu/Sources/FricuApp/Resources/shiba_inu.usdz"
    
    # Perform the conversion
    convert_glb_to_usdz(glb_file, usdz_file)
