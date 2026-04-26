UltimateEQAssist Level-80 Preset Matrix

This folder contains generated level-80 presets for all classes:
- Classes: WAR CLR PAL RNG SHD DRU MNK BRD ROG SHM NEC WIZ MAG ENC BST BER
- Presets: SOLO GROUP RAID
- Total files: 48

Generation strategy:
- If a Level80 class source exists (L80 PAL/MNK/BRD/ENC/WIZ/SHM), it is used as base.
- Otherwise, the class template UltimateEQAssist_<CLASS>.ini is used as base.
- Setup preset overlays are applied to keep behavior consistent with MAUI Setup Mode.

Preset overlays applied:
- Common: AcceptInvitesOn=1, BuffWhileChasing=1, MedOn=1, MedStart=30, CastRetries=3
- SOLO: ChaseAssist=0, ReturnToCamp=1, CampRadius=35, ChaseDistance=25
- GROUP: ChaseAssist=1, ReturnToCamp=0, CampRadius=30, ChaseDistance=25
- RAID: ChaseAssist=1, ReturnToCamp=0, CampRadius=30, ChaseDistance=35
- Enabled modules: DPS/Buffs/Heals/Cures On (+ COn where present)

Review and tune spell/disc/item names for your server and rank availability.
