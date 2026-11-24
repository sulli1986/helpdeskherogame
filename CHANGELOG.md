# Changelog

## Day 17 — 2026-11-25
- Stuck on a ticket? Ask a Senior: press the new button under the answers (or H) and a senior tech gives you a hint
- Every ticket, and every step of a multi-step one, has three hints: where to look, what the evidence means, then exactly what to do. Your latest hint also shows at the top of the tool you're working in
- Each hint costs a quarter of that step's pay, so solving it yourself still pays best. Your shift summary counts how many you asked for

## Day 16 — 2026-11-24
- Locked out by BitLocker: a new ticket where the caller's laptop is stuck on the blue recovery screen. Find their key in Accounts and read it out
- First check the callback number against the mobile on file. Then open their devices and match the key ID on their screen: not their old laptop's, not the data drive's, not an older key for the same drive
- Unverified caller, or no key in Entra with that ID? Read out nothing and hold. Every key you read out counts, so a wrong one escalates the ticket

## Day 15 — 2026-11-23
- Stop the 2am attacker yourself: MFA fatigue tickets are now worked in Accounts. Open the caller's sign-in log, sessions, MFA methods and inbox rules
- Did a push get approved? Then revoke every session and remove what the attacker left: their own Authenticator, a hidden inbox rule, both or neither. Always reset the password and require a change at next sign-in
- Leave the user's own phone and rules alone, never turn MFA off or trust the attacker's IP, and unblock sign-in before you close it. The old tick-box admin console is gone

## Day 14 — 2026-11-22
- Fix the outage yourself: once you've diagnosed "The internet is down!", the fix step happens on the Network Map, now with the client's ISP, modem, firewall and domain controller
- Find out why: the ISP's status page, the modem's lights, the firewall's links, rules and log, and the domain controller's DNS forwarders, DHCP and event log. Then fix the cause: new forwarders, a narrow firewall rule, the modem's power, the DHCP service or its authorisation
- An ISP outage? Log the fault, fail over to the 4G/5G backup if the site has one, and hold. Factory resets, switching off a firewall rule, or pointing PCs at public DNS all count against you

## Day 13 — 2026-11-21
- Trace the dead printer yourself: "Printer not printing" tickets are now worked on the Network Map, a new Toolbox tab with the client's firewall, switch, print server and printers
- Ping it from the print server, open its web page, check the switch ports and the firewall's DHCP leases, or ask the caller to read its screen. Then fix it: cancel the stuck job, resume the queue, re-point the port at the printer's new address and reserve it, or get the cable plugged back in
- Out of toner with no spare, or a hardware fault? Order it or log the vendor call, then put the ticket on hold. Clearing the spool folder throws away everyone's jobs, so it counts against you

## Day 12 — 2026-11-20
- Deal with phishing yourself: reported emails are now worked in the Mail Console, a new Toolbox app in its own tab. Find the email they mean in today's message trace and read its headers
- A phish? Delete it from every mailbox it reached, then block the right thing: the scammer's address, the attacker's own lookalike domain, or the fake sign-in link. Never block all of Gmail, or a real supplier whose mailbox was hacked
- Legit but quarantined? Release it. A bank-detail change from a real supplier? Change nothing and hold until someone phones them on a number you already have

## Day 11 — 2026-11-19
- License the new starter yourself: "New starter Monday" tickets are now done in Accounts. Find the starter (not their namesake) and assign their Microsoft 365 licence
- Pick the cheapest licence that covers their needs: Basic for phone and browser only, Standard for desktop Office apps, Premium when the laptop must be managed with Intune and Defender
- None spare? If a leaver's mailbox is already a shared mailbox, free their licence and reuse it. No leaver? Hold and get the client's approval to buy one. Never take a licence from someone who still works there

## Day 10 — 2026-11-18
- Remote onto their PC: new scanner tickets are fixed in Remote Control, a Toolbox app in its own tab. Connect to the caller's PC (not their namesake's), then use its Device Manager, Settings and browser
- Check the hardware ID in Device Manager and the processor in Settings, then install the vendor's driver for that exact model: x64 or Arm. Users don't always name the right model
- No Arm driver for that scanner? Install nothing and hold. Every install counts: the "driver updater" ad, the wrong package or anything on the wrong PC escalates the ticket

## Day 9 — 2026-11-17
- Do the fix yourself: lockout and file-access tickets are now worked in Accounts, a Toolbox app in its own tab beside the ticket. Tap the Accounts tab or press T, then come back to the Ticket tab to close it
- Find the right user (watch for colleagues with the same first name), check their mobile on file against the callback, then unlock, reset and require a new password at next sign-in
- Access requests: tick the right group (Read or Modify) and nothing more, or hold if the manager hasn't approved. Change the wrong account, or anything you shouldn't, and the ticket escalates

## Day 8 — 2026-11-16
- Lock it down yourself: MFA fatigue tickets now open an admin console. Tick every action the account needs, then Apply
- First read the sign-in logs: did MFA hold, or did the attacker get in? Then reset, revoke, remove their Authenticator and their sneaky inbox rule, but leave the user's own rules alone
- Miss a must-do step or tick something harmful (like turning MFA off) and the ticket escalates. Keys 1-9 tick actions on a keyboard, Enter applies
- Calmer shifts: a shift now lasts ten minutes, new tickets arrive every 35-50 seconds instead of every 10-18, and hold off while three sit unopened, and SLAs are longer, with extra time for every step a ticket has

## Day 7 — 2026-11-15
- Printers get a proper diagnosis: "Printer not printing" tickets now have two steps. First work out whether it's the print queue, the network or the printer itself, then pick the fix
- Read the clues: does the printer answer ping? Is its web page reachable? Then open the queue, check the switch and DHCP leases, or get the user to read the control panel
- Stuck job or paused queue? New IP address or an unplugged cable? Out of toner or a fuser fault for the vendor? Each step pays, and a wrong call still escalates the ticket

## Day 6 — 2026-11-14
- Prove it's fixed: "The internet is down!" tickets now have a third step. After the fix, you're back on the user's command prompt and must pick the test result that proves the network really works
- Only the test that failed before counts: a reply from the router or DC01 proved nothing while it was broken. After a DHCP fix the PC keeps its old 169.254 address until you run ipconfig /renew
- Each of the three steps pays, and a wrong call on any of them still escalates the ticket

## Day 5 — 2026-11-13
- Find it, then fix it: "The internet is down!" tickets now have two steps. Diagnose the fault in the command prompt, then remote onto the server or router and pick the right fix
- Each step pays, but a wrong fix still escalates the ticket. Was it a dead DNS forwarder or a new firewall rule? A stopped DHCP service or one that was never authorised? An ISP outage or a modem with no power?
- Rebuilt for phones: the queue and the open ticket each get the whole screen (tap "‹ Queue" to go back), you can swipe to scroll from anywhere, even on an answer, and a big Next button follows every result. Text is bigger, sideways too

## Day 4 — 2026-11-12
- Type real commands to find the fault: "The internet is down!" tickets put you on the phone with the user, typing commands into their PC's command prompt
- The evidence starts hidden: run ipconfig, ping, nslookup and tracert yourself to work out if it's DNS, the ISP link or DHCP
- On a phone, tap the command buttons under the prompt (swipe for more) instead of typing. On a keyboard, Up and Down recall earlier commands and Esc leaves the prompt so 1-4 answer again

## Day 3 — 2026-11-11
- MFA fatigue attack at 2am: a new ticket where a user's phone won't stop buzzing with sign-in requests they didn't start
- Read the Entra sign-in and audit logs: did MFA hold, or did someone get in? Pick the right containment
- Watch for the tell-tale signs of a takeover: a new Authenticator on the account and a sneaky inbox rule

## Day 2 — 2026-11-10
- The helpdesk has sound: a chime for every new ticket, a jingle for a fix, a buzz for a wrong call and a beep when a ticket's SLA is nearly up
- Press M or the Sound button in the top bar to mute; it remembers your choice
- On phones the top bar no longer runs off the edge of the screen

## Day 1 — 2026-11-09
- Welcome to the helpdesk: run a shift at an MSP and work tickets before their SLA runs out
- Six kinds of ticket: phishing checks, account lockouts, share access, printers, internet outages and M365 licences
- Read the evidence (headers, AD, ping output), pick the fix with 1-4, and see why it was right or wrong
- Faster fixes pay more; wrong calls and SLA breaches cost reputation. Lose it all and the client walks
- Make an account to save your career cash and climb the leaderboard
- This "What's new" panel: press V or click the button in the bottom-left
