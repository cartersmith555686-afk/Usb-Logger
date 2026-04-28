# 1. git clone https://github.com/cartersmith555686-afk/Usb-Logger/tree/main

# 2. Install
bash install_no_root.sh

# 3. Connect target via USB-C OTG cable
#    Make sure USB Debugging is ON on the target

# 4. Extract everything
bash extract_no_root.sh

# 5. Analyze results
python3 analyze_no_root.py android_extract_*/
