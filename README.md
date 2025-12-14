# Servo 🪄

A simple and interactive script to set up and harden a fresh Ubuntu VPS.

## Installation and Usage

**Servo** is meant to be used on a freshly provisioned Ubuntu VPS.

1. _SSH_ into your machine, as _root_.

2. Download the latest release (currently: **v0.0.0**) of `servo.sh`:

```bash
$ curl -O https://raw.githubusercontent.com/mjsarfatti/servo/refs/tags/v0.0.0/dist/servo.sh
```

3. Make sure the script is executable, then run it:

```bash
$ chmod +x servo.sh
$ ./servo.sh
```

PS: you can invoke the script with `--dry-run` to see every command it would launch.

```bash
$ ./servo.sh --dry-run
```

## What It Does

1. **Create a non-root _sudo_ user**  
   → You will be asked to choose a username

2. **Set up SSH key authentication**  
   → You will be asked to paste your public key, make sure you have it already created and handy

3. **Harden the SSH configuration**  
   → You will be able to specify an alternative port to _22_  
   → You will be able to prohibit _root_ login either entirely, or keeping key-based login open

4. **Update and upgrade the system**

5. **Install essential packages**  
   (`build-essential`, `git`, `ufw`, `fail2ban`)

6. **Enable unattended upgrades**  
   (security patches only)

7. **Configure `fail2ban`**

8. **Configure `ufw` (firewall)**  
   (it will make sure to open the SSH port you specified above)
