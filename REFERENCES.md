# Références techniques

Le lecteur matériel et l’interface de MacSensors sont implémentés dans ce projet. Les identifiants matériels et le format du protocole SMC ont été vérifiés à partir de ces références publiques ; aucune bibliothèque de ces projets n’est embarquée.

- Apple AppKit, NSStatusItem : https://developer.apple.com/documentation/appkit/nsstatusitem
- Apple IOKit, IOConnectCallStructMethod : https://developer.apple.com/documentation/iokit/1514240-ioconnectcallstructmethod
- Apple XNU, compteurs mémoire : https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h
- AppleSMC : format de message de 80 octets et commandes de lecture documentés notamment par SMCKit : https://github.com/beltex/SMCKit/blob/master/SMCKit/SMC.swift
- Identifiants des zones M3 et noms matériels HID, projet Stats : https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift
- Informations sur les limites d’interprétation des zones M3, éditeur TG Pro : https://www.tunabellysoftware.com/blog/files/tg-pro-apple-silicon-m3-series-support.html

Les noms de zones constituent une nomenclature logicielle et ne sont pas une preuve du nombre de sondes physiques. Les interfaces de température utilisées ne constituent pas une API publique stable garantie par Apple.

## Révision des clés thermiques dans la version 1.2

Les tables communautaires des clés M3 se contredisent sur la famille Tf. Le choix conservateur est de garder ces clés non identifiées, de ne pas leur attribuer automatiquement des degrés Celsius et de privilégier TCMb pour le relevé CPU central.

- Comparaison des familles et observations sur des constantes Tf : https://github.com/sebhildebrandt/macos-smc/blob/main/docs/smc-keys.md
- Relevés CPU agrégés utilisés par OSHI : https://www.oshi.ooo/xref/oshi/util/platform/mac/SmcUtil.html

Ces références ne remplacent pas une documentation matérielle Apple ni une validation de chaque clé sur la machine de l’utilisateur.
