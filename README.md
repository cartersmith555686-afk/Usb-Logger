# 1. Install
bash install_no_root.sh

# 2. Connect target via USB-C OTG cable
#    Make sure USB Debugging is ON on the target

# 3. Extract everything
bash extract_no_root.sh

# 4. Analyze results
python3 analyze_no_root.py android_extract_*/
