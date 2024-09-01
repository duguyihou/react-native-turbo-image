import { RouteName } from './screens/routes.type';

export const routesData = [
  {
    title: 'List',
    data: [
      { name: 'React Native Image', destination: RouteName.Image },
      {
        name: 'TurboImage with UrlCache (default)',
        destination: RouteName.UrlCache,
      },
      { name: 'TurboImage with DataCache', destination: RouteName.DataCache },
    ],
  },
  {
    title: 'Placeholder',
    data: [
      { name: 'thumbhash', destination: RouteName.Thumbhash },
      { name: 'blurhash', destination: RouteName.Blurhash },
      { name: 'memoryCacheKey', destination: RouteName.MemoryCacheKeyPrevious },
    ],
  },
  {
    title: 'Prefetch',
    data: [
      {
        name: 'PrefetchWithUrlCache',
        destination: RouteName.PrefetchWithUrlCache,
      },
      {
        name: 'PrefetchWithDataCache',
        destination: RouteName.PrefetchWithDataCache,
      },
    ],
  },
  {
    title: 'Events',
    data: [
      { name: 'Start -> Completion(Success)', destination: RouteName.Success },
      { name: 'Start -> Completion(Failure)', destination: RouteName.Failure },
    ],
  },
  {
    title: 'Image Processing',
    data: [{ name: 'Processing', destination: RouteName.ImageProcessing }],
  },
  {
    title: 'Live Text',
    data: [{ name: 'iOS 16+ only', destination: RouteName.LiveText }],
  },
  {
    title: 'Other Formats(Experimental)',
    data: [
      { name: 'SVG', destination: RouteName.SVG },
      { name: 'Gif', destination: RouteName.Gif },
      { name: 'APNG', destination: RouteName.APNG },
    ],
  },
];
export const dataCachelistData = [
  {
    url: 'https://placedog.net/300/300?id=1',
    blurhash: 'ULKKWp^+s,_300M{t7tR~XNHE2bI00xuWBRP',
  },
  {
    url: 'https://placedog.net/300/300?id=2',
    blurhash: 'U8E{gx$yEd-.Q6S#IVWC1tXSRAM|rqwJ=_xZ',
  },
  {
    url: 'https://placedog.net/300/300?id=16',
    blurhash: 'UGGuwT014.xa?w.9w{M{~qWZt7ocs:tRoyV@',
  },
  {
    url: 'https://placedog.net/300/300?id=28',
    blurhash: 'UWI~1OxwEXog9VM}IWt8Ibj=-gRjD,xZxoWE',
  },
  {
    url: 'https://placedog.net/300/300?id=33',
    blurhash: 'UDFPNjIT9ZxW_NWZxuIT0LR:s:IUSNt7aJt6',
  },
  {
    url: 'https://placedog.net/300/300?id=25',
    blurhash: 'UWQbCFMc^kxu}]-WWAf6?ckWE0s8xaOCNdkD',
  },
  {
    url: 'https://placedog.net/300/300?id=30',
    blurhash: 'UMM7y1?wE#NI0hIVRPt7BEjE#l%19Gxu%fRj',
  },
  {
    url: 'https://placedog.net/300/300?id=55',
    blurhash: 'UOIY2.%19bkr~qt7t8ay9Zf+%1n$x_ofMxof',
  },
  {
    url: 'https://placedog.net/300/300?id=59',
    blurhash: 'UjLXSxM_Rkso_NV@IUM{.7%Mayozt8oLxuju',
  },
  {
    url: 'https://placedog.net/300/300?id=41',
    blurhash: 'URKAZr~Bs;xD00ngV?oe%0WA%LkB%2xZNHWV',
  },
  {
    url: 'https://placedog.net/300/300?id=82',
    blurhash: 'U6F~Kx^*8w=rR3S%?bR3rTIr%N?b~V-;ITD*',
  },
  {
    url: 'https://placedog.net/300/300?id=34',
    blurhash: 'UMLzsu-TQ--o_4%LV?kV?bIVN_WV?F-Uofju',
  },
  {
    url: 'https://placedog.net/300/300?id=65',
    blurhash: 'UVMj5K~q-;tR~VNJRjae?vIUIUV?EN-Us:of',
  },
  {
    url: 'https://placedog.net/300/300?id=6',
    blurhash: 'U5DvZh00.9~WRi9ZD%ofD*%M%2og4oWB%Lof',
  },
  {
    url: 'https://placedog.net/300/300?id=12',
    blurhash: 'USKT@|1YNEr=%$~CM|E1tl?HoMbb^+NGozxu',
  },
  {
    url: 'https://placedog.net/300/300?id=10',
    blurhash: 'U3Bfg:05SWtj01xaSTMx07xU8~%304xs~SM|',
  },
  {
    url: 'https://placedog.net/300/300?id=78',
    blurhash: 'USOV}w_N%NaK?bWBflt7?bM{IUt7%MjYj[WB',
  },
  {
    url: 'https://placedog.net/300/300?id=15',
    blurhash: 'UACGY%~q00008}IVWFxv00E0-?_3tR%LbEM{',
  },
  {
    url: 'https://placedog.net/300/300?id=9',
    blurhash: 'UPIEto%1S2bH_NE1M{t7%g%LxZxu-p%Ls:R*',
  },
  {
    url: 'https://placedog.net/300/300?id=4',
    blurhash: 'UGG8vGDiD%^,~Cx]aft60K%gRjIU?wRPadM_',
  },
  {
    url: 'https://placedog.net/300/300?id=3',
    blurhash: 'U9E_ml~A00xaLMENDi9wO[X8v}-;xvxatP~V',
  },
  {
    url: 'https://placedog.net/300/300?id=8',
    blurhash: 'UJG8yAs-_2t7?wD%?bx[4;D%%MxuxBW9IUM|',
  },
  {
    url: 'https://placedog.net/300/300?id=5',
    blurhash: 'UJD9t~_MM^IS0dITo#x]IUNGx]t8xvt8oMV?',
  },
  {
    url: 'https://placedog.net/300/300?id=57',
    blurhash: 'UGBphER*xu^,_4-:x]?bIV?b?Ht8NH-;-:NG',
  },
  {
    url: 'https://placedog.net/300/300?id=68',
    blurhash: 'UMMHDRD$?w?bxuxukDD%D%WARiRk?bRjog%M',
  },
  {
    url: 'https://placedog.net/300/300?id=17',
    blurhash: 'UDI}hf-.yEIV00V?4Tx]00X9R-ROIBWF_4M{',
  },
  {
    url: 'https://placedog.net/300/300?id=67',
    blurhash: 'UZK^vw_4V@$%.8-pSht79ZRi%MkW^+M|%2oz',
  },
  {
    url: 'https://placedog.net/300/300?id=19',
    blurhash: 'UyLqh5ofs*j]~qoeWAfl%2ofR,of?Hogs;oI',
  },
  {
    url: 'https://placedog.net/300/300?id=86',
    blurhash: 'UBEM2d-:s:%M00bDafM|_4jcM|IU00V]xuxt',
  },
  {
    url: 'https://placedog.net/300/300?id=62',
    blurhash: 'UMFih_xt0N9aT5W=%Ln~AfNbwh-Uu5t7RPNG',
  },
  {
    url: 'https://placedog.net/300/300?id=18',
    blurhash: 'ULMkeUr:aJ?w-;M{NHogT1tSbIaJ.8%LxaRj',
  },
  {
    url: 'https://placedog.net/300/300?id=107',
    blurhash: 'U8D+oK-pD%9F8_InMw~W}@Io_3of_3bJ4nE1',
  },
  {
    url: 'https://placedog.net/300/300?id=102',
    blurhash: 'UALqLS?F00%L00%N00D*E49FXno~~oIA%h_3',
  },
  {
    url: 'https://placedog.net/300/300?id=11',
    blurhash: 'U8G8yC~CHs^i5Pt*-qxu0MR;$j0L0f0LXmix',
  },
  {
    url: 'https://placedog.net/300/300?id=58',
    blurhash: 'U6C6}vIA009F00.8nMRi.9IU_N-=yEt7%2Rj',
  },
  {
    url: 'https://placedog.net/300/300?id=92',
    blurhash: 'UFF=?i0000_Nsn-:9Faf00%M-=RjE1Rj?bRi',
  },
  {
    url: 'https://placedog.net/300/300?id=75',
    blurhash: 'U3AdAf010d_08xDi-;ot00n4}u0JOcN4w|Mx',
  },
  {
    url: 'https://placedog.net/300/300?id=108',
    blurhash: 'UELgna]x%$o~_4i^V@V@.TWBIAt7?bkDWBxu',
  },
  {
    url: 'https://placedog.net/300/300?id=7',
    blurhash: 'UECZb3%LnOJ6DjS5tRV[ixs;IoxG~C-VxbtQ',
  },
  {
    url: 'https://placedog.net/300/300?id=23',
    blurhash: 'UuNA#Y_Nt7Mx-;Rjj[t7%MM{Rjt7%MRjRjj[',
  },
  {
    url: 'https://placedog.net/300/300?id=79',
    blurhash: 'UDBzB^?H9FR$5Wo#MxDi%gkDadRP~VxaIooc',
  },
  {
    url: 'https://placedog.net/300/300?id=87',
    blurhash: 'UCGbq;$.9Y%y?pVtITR$00-;%4D%_4x]t8Mx',
  },
  {
    url: 'https://placedog.net/300/300?id=21',
    blurhash: 'UfI=rhJ#O7V]-rxcRjWU~XM{Rlt7%JSJWBM{',
  },
  {
    url: 'https://placedog.net/300/300?id=111',
    blurhash: 'UHBpkG4o4m~q9Y%2g4RP9F%2-;D%%gM{nNtR',
  },
  {
    url: 'https://placedog.net/300/300?id=40',
    blurhash: 'UKHCJ}tRSjxZ?wj]WqflInaenhf+%hj]oJoL',
  },
  {
    url: 'https://placedog.net/300/300?id=27',
    blurhash: 'UIH-ri%2E34n~BMxIVROpcDiIVxYbxROx]g3',
  },
  {
    url: 'https://placedog.net/300/300?id=73',
    blurhash: 'UEH1k^%LD*={=?xZElad~UIpaJt70MkC?GV@',
  },
  {
    url: 'https://placedog.net/300/300?id=38',
    blurhash: 'U7F=ge9Z9FIo?bE1Di-oxCxa0MX9~Vt7NGIo',
  },
  {
    url: 'https://placedog.net/300/300?id=13',
    blurhash: 'U37287_2015*1hX,^keU-=R.IV$k*HeVxtxs',
  },
  {
    url: 'https://placedog.net/300/300?id=14',
    blurhash: 'UCG8r{BY0U~q00xoX9xUIRv_}+ITskM{t7Si',
  },
  {
    url: 'https://placedog.net/300/300?id=54',
    blurhash: 'UHF=%K4njEV@S5t7IV9F00~qbIIU-oju%2?b',
  },
  {
    url: 'https://placedog.net/300/300?id=112',
    blurhash: 'UMDbvXi^9FR*-Os:R+WBDgxu%Nja~Aada#og',
  },
  {
    url: 'https://placedog.net/300/300?id=61',
    blurhash: 'UVNmpDMx-;?b-;ofRjof_N%gIUM{tRWBxaWB',
  },
  {
    url: 'https://placedog.net/300/300?id=47',
    blurhash: 'U25qR{0zJ7$i0zoLIp^jWB%1NHNaShae^P0z',
  },
  {
    url: 'https://placedog.net/300/300?id=113',
    blurhash: 'UNG*vaNG0Kxu~qf6D%R*D%ogofRk5Qt7xaWX',
  },
  {
    url: 'https://placedog.net/300/300?id=20',
    blurhash: 'UYJQ_R%K9txq}?ozIrV]VeRVRojbxaofWBoe',
  },
  {
    url: 'https://placedog.net/300/300?id=70',
    blurhash: 'ULLDlbI9?woMDho#kCRPtlWBR*og-;RjR*t7',
  },
  {
    url: 'https://placedog.net/300/300?id=24',
    blurhash: 'UyNd2T_NozMx%Mfkaxay%MM{jZt7xabHWVs:',
  },
  {
    url: 'https://placedog.net/300/300?id=36',
    blurhash: 'UBHnZxPW0qSi}mxZT0t7o}M{WEjE-;Ndo}Dj',
  },
  {
    url: 'https://placedog.net/300/300?id=26',
    blurhash: 'UlLp{a?a%Mxt~oNIkBxt-:M|Rjj[tSxZWBR*',
  },
  {
    url: 'https://placedog.net/300/300?id=81',
    blurhash: 'UXO3;0*0%M%M-=ITIpadyEVrM{Ioo}RioIkC',
  },
  {
    url: 'https://placedog.net/300/300?id=72',
    blurhash: 'UQI}V2-;_N-;xbV@RjRkXARiNGoz-;jYfkt7',
  },
  {
    url: 'https://placedog.net/300/300?id=39',
    blurhash: 'UuIhKnWDT0t7.TxuafWX.9bHnioK%gj@sloe',
  },
  {
    url: 'https://placedog.net/300/300?id=46',
    blurhash: 'UDI}q*%NWZ-:00D%D$M{Ne?bob-;~pWBtSM{',
  },
  {
    url: 'https://placedog.net/300/300?id=52',
    blurhash: 'U7G8N3w[00-:=}E19Z0K_3^+jFIU_M4.s:~q',
  },
  {
    url: 'https://placedog.net/300/300?id=42',
    blurhash: 'UHHoF2WSIXV?_4xuIVIU?c%MbI-;~qjZofx]',
  },
  {
    url: 'https://placedog.net/300/300?id=48',
    blurhash: 'UABpwbM_00%g_LoeD%WV00t7^lRP8_WC?bjr',
  },
  {
    url: 'https://placedog.net/300/300?id=44',
    blurhash: 'UD6cTae9NGS$r?g3kCoJLgozn4ozu4iwS4S$',
  },
  {
    url: 'https://placedog.net/300/300?id=45',
    blurhash: 'U7D+Vgxu00Fh5-xun5t500Rn~Vox01jY.7t2',
  },
  {
    url: 'https://placedog.net/300/300?id=22',
    blurhash: 'UCGIr;01xp?b_4t5M|M{xtxvt8oM~pt7Dioy',
  },
  {
    url: 'https://placedog.net/300/300?id=31',
    blurhash: 'UOLMeK~q%$%M0#?GM|kD4:IUVYV?xZEMxts,',
  },
  {
    url: 'https://placedog.net/300/300?id=91',
    blurhash: 'U6D]o5~p9G0LIoX9%MnN%LMwNI-;~q%LRPof',
  },
  {
    url: 'https://placedog.net/300/300?id=37',
    blurhash: 'UaIrcraR%Nx-~UITt7W9ICR#ofMyo{t6ogW-',
  },
  {
    url: 'https://placedog.net/300/300?id=53',
    blurhash: 'U7E3F;Dhbb?w4mkB-;ng00%0xuITX9nfM|IW',
  },
  {
    url: 'https://placedog.net/300/300?id=56',
    blurhash: 'ULI;^yXUNHS%JW%g-p%MI@ofodxa~qt79Fjs',
  },
  {
    url: 'https://placedog.net/300/300?id=69',
    blurhash: 'URM@P^-nx]D%~ps+xuV[bb9FRjjY?bxuogof',
  },
  {
    url: 'https://placedog.net/300/300?id=63',
    blurhash: 'U8EDE^+h8SyU04-nNGXgGWUUVIR74VHwR8M|',
  },
  {
    url: 'https://placedog.net/300/300?id=29',
    blurhash: 'UzF=,?w[o$WsA#RPWEogR;WBaIobi^t7n}ad',
  },
  {
    url: 'https://placedog.net/300/300?id=35',
    blurhash: 'UCF~58WZtk-o0i%fD*E1~TIVW;e-bJRjxtxu',
  },
  {
    url: 'https://placedog.net/300/300?id=66',
    blurhash: 'UIH-xx~pDODOE2xuoeNFi^D*xuxv-:x[WBRQ',
  },
  {
    url: 'https://placedog.net/300/300?id=64',
    blurhash: 'ULF$Ik-:9uE1%gxuIoM{.8WCROj@~Vs:V@WB',
  },
  {
    url: 'https://placedog.net/300/300?id=32',
    blurhash: 'U7E{?Y?bR#ta_Ja#R*ovNWkPRWRYX3k9ofn,',
  },
  {
    url: 'https://placedog.net/300/300?id=77',
    blurhash: 'UGGuaJ?wR+MvD,R*M{V[00D$RktS56jFxutR',
  },
  {
    url: 'https://placedog.net/300/300?id=80',
    blurhash: 'UCEo6[?aDiMe~oR*D%n+x]t6IVRjnOaextt7',
  },
  {
    url: 'https://placedog.net/300/300?id=71',
    blurhash: 'UbI;x9-:Ioxu-PIAIoof~qWBa}ofozkCxuWB',
  },
  {
    url: 'https://placedog.net/300/300?id=101',
    blurhash: 'UxH.Ww~q_3%N%NRjfQWB%MV@WBae-;ayayRj',
  },
  {
    url: 'https://placedog.net/300/300?id=115',
    blurhash: 'UECPL#IU0f-:}nNGNHt6NxR*-oRP%#jFayRk',
  },
  {
    url: 'https://placedog.net/300/300?id=43',
    blurhash: 'UDCaeN^nIA53txaeoeov9;Imxu-r-:t8V^V[',
  },
  {
    url: 'https://placedog.net/300/300?id=93',
    blurhash: 'UHHBxX~B0wEf02E2=z-oD*RkajjZ$|SeSLRk',
  },
  {
    url: 'https://placedog.net/300/300?id=49',
    blurhash: 'UMF5,AWA57?a$*W=E2%LIUogogoJ~Vs,xue-',
  },
  {
    url: 'https://placedog.net/300/300?id=104',
    blurhash: 'UGG*~C4:9a~U00V?ofkDyY^+of9ZIURPjYWC',
  },
  {
    url: 'https://placedog.net/300/300?id=83',
    blurhash: 'UhHx7q~nf~IVnVIua$xWROM{oft7s%avt6xb',
  },
  {
    url: 'https://placedog.net/300/300?id=74',
    blurhash: 'URG[NC~A0K57$*xaS1R*Ezbbo2RQxtWBWBkC',
  },
  {
    url: 'https://placedog.net/300/300?id=51',
    blurhash: 'ULFQKkoz.hx@KYo]fhM|-:xtMOV_%dM|jJx@',
  },
  {
    url: 'https://placedog.net/300/300?id=88',
    blurhash: 'URE#fORl*8yS%fbYout6pTkSR8V_Rjjbf%ay',
  },
  {
    url: 'https://placedog.net/300/300?id=95',
    blurhash: 'UUK-2t^*9Gt6.So~kDxa.Ttls:x^?wenMwn$',
  },
  {
    url: 'https://placedog.net/300/300?id=119',
    blurhash: 'UTHe:*~q9FE100InM{IUDjM{%Mxbt7t7%Mxu',
  },
  {
    url: 'https://placedog.net/300/300?id=89',
    blurhash: 'UMGkm~IoD$%L~VV?Riae_1WA%LxuxYoIxuoe',
  },
  {
    url: 'https://placedog.net/300/300?id=118',
    blurhash: 'UCBWY#_M57yDg2-;?akWIXIWeT$*4:IVxbV]',
  },
  {
    url: 'https://placedog.net/300/300?id=110',
    blurhash: 'U4Av@1}?*05r00IVRjV@0fIqVr?G4n.7IUD%',
  },
  {
    url: 'https://placedog.net/300/300?id=50',
    blurhash: 'UWMQ;e_3_4t8_3tRoeM{?cD$WBxu?bWBIUxu',
  },
  {
    url: 'https://placedog.net/300/300?id=117',
    blurhash: 'UeH2NA-pxbRj?bIV%LWB_NtRxukC-;s:jZf6',
  },
  {
    url: 'https://placedog.net/300/300?id=90',
    blurhash: 'UAFX^$8_*J9ZPB4Tt7t7.7xu$%xaSNIpwuWE',
  },
  {
    url: 'https://placedog.net/300/300?id=105',
    blurhash: 'UGI53z00RO~V_2?bROV@-:-otRs.=^-;kAay',
  },
  {
    url: 'https://placedog.net/300/300?id=97',
    blurhash: 'UMIr8I00?w-p00M_ozMwp0?cM_R+Mwf5WXt7',
  },
  {
    url: 'https://placedog.net/300/300?id=99',
    blurhash: 'UVIXKF-Uy6--~TX7IpWEo|ovM{fS%doJV@bF',
  },
  {
    url: 'https://placedog.net/300/300?id=85',
    blurhash: 'UXEyktWUS]Rl~mk8xtj]x?oMxat5odahWFxs',
  },
  {
    url: 'https://placedog.net/300/300?id=98',
    blurhash: 'UiIOm}%etQRR-@j^ogj=%haNa#od%MobWBWF',
  },
  {
    url: 'https://placedog.net/300/300?id=60',
    blurhash: 'UMN]peI3kP?j~RI[WFt2tkxrIXM#-pxaxTE3',
  },
  {
    url: 'https://placedog.net/300/300?id=84',
    blurhash: 'UKKwzr009w4n?wWXDiMynhxtIUe..8IBWUtR',
  },
  {
    url: 'https://placedog.net/300/300?id=76',
    blurhash: 'UJH_A29FD*%L#*%2o#M|_NVr?Gxu-;NIskxu',
  },
  {
    url: 'https://placedog.net/300/300?id=96',
    blurhash: 'UBHm=QIotRX:}WxvIq%f={I]W?9w}=Acsm%2',
  },
  {
    url: 'https://placedog.net/300/300?id=120',
    blurhash: 'UAH27p9E0Kxu%g%gNFRi58tSVsn%~q4mxvxv',
  },
  {
    url: 'https://placedog.net/300/300?id=94',
    blurhash: 'U7Am#XNX0J~q:+ogK%D%%1R*IWahT0f*xYWB',
  },
  {
    url: 'https://placedog.net/300/300?id=106',
    blurhash: 'U6D016w[00IU4V%300R-%$NG~Wxu0LIU~V-;',
  },
  {
    url: 'https://placedog.net/300/300?id=116',
    blurhash: 'U68;_4Rj?=.6D+M#VuIV5NMm8}InIV.PtPoy',
  },
  {
    url: 'https://placedog.net/300/300?id=100',
    blurhash: 'UFIzYG04xZ~UM{=_9uM{9w^ONHE2Xn=_s.oz',
  },
  {
    url: 'https://placedog.net/300/300?id=103',
    blurhash: 'UACZCRIT0L~p00xZ?H9a02W?-VIV=qbx4:-o',
  },
  {
    url: 'https://placedog.net/300/300?id=114',
    blurhash: 'UUJtxL?cD$%2IAs.NGRi~q%MV@R*NHt6R*WB',
  },
  {
    url: 'https://placedog.net/300/300?id=109',
    blurhash: 'UUJbG}WRITxw~Tt6tRoer;xbs=R#%4WBRjkB',
  },
];

// copied from https://github.com/kean/NukeDemo/blob/main/Sources/Helpers/Images.swift#L8
export const urlCacheListData = [
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781817/ecb16e82-57a0-11e5-9b43-6b4f52659997.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781832/0719dd5e-57a1-11e5-9324-9764de25ed47.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781833/09021316-57a1-11e5-817b-85b57a2a8a77.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781834/0931ad74-57a1-11e5-9080-c8f6ecea19ce.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781838/0e6274f4-57a1-11e5-82fd-872e735eea73.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781839/0e63ad92-57a1-11e5-8841-bd3c5ea1bb9c.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781843/0f4064b2-57a1-11e5-9fb7-f258e81a4214.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781840/0e95f978-57a1-11e5-8179-36dfed72f985.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781841/0e96b5fc-57a1-11e5-82ae-699b113bb85a.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781894/839cf99c-57a1-11e5-9602-d56d99a31abc.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781896/83c5e1f4-57a1-11e5-9961-97730da2a7ad.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781897/83c622cc-57a1-11e5-98dd-3a7d54b60170.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781900/83cbc934-57a1-11e5-8152-e9ecab92db75.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781899/83cb13a4-57a1-11e5-88c4-48feb134a9f0.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781898/83c85ba0-57a1-11e5-8569-778689bff1ed.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781895/83b7f3fa-57a1-11e5-8579-e2fd6098052d.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781901/83d5d500-57a1-11e5-9894-78467657874c.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781902/83df3b72-57a1-11e5-82b0-e6eb08915402.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781903/83e400bc-57a1-11e5-881d-c0ed2c5136f6.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781964/f4553bea-57a1-11e5-9abf-f23470a5efc1.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781955/f3b2ed18-57a1-11e5-8fc7-0579e44de0b0.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781959/f3b7e624-57a1-11e5-8982-8017f53a4898.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781957/f3b52e98-57a1-11e5-9f1a-8741acddb12d.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781958/f3b5544a-57a1-11e5-880a-478507b2e189.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781956/f3b35082-57a1-11e5-9d2f-2c364e3f9b68.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781963/f3da11b8-57a1-11e5-838e-c75e6b00f33e.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781961/f3d865de-57a1-11e5-87fd-bb8f28515a16.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781960/f3d7f306-57a1-11e5-833f-f3802344619e.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781962/f3d98c20-57a1-11e5-838e-10f9d20fbc9b.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781982/2b67875a-57a2-11e5-91b2-ec4ca2a65674.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781985/2b92e576-57a2-11e5-955f-73889423b552.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781986/2b94c288-57a2-11e5-8ebd-4cc107444e70.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781987/2b94ba72-57a2-11e5-8259-8d4b5fce1f6c.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781984/2b9244ea-57a2-11e5-89b1-edc6922d1909.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781988/2b94f32a-57a2-11e5-94f6-2c68c15f711f.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781983/2b80e9ca-57a2-11e5-9a90-54884428affe.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781989/2b9d462e-57a2-11e5-8c5c-d005e79e0070.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781990/2babeeae-57a2-11e5-828d-6c050683274d.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781991/2bb13a94-57a2-11e5-8a70-1d7e519c1631.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781992/2bb2161c-57a2-11e5-8715-9b7d2df58708.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781993/2bb397a8-57a2-11e5-853d-4d4f1854d1fe.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781994/2bb61e88-57a2-11e5-8e45-bc2ed096cf97.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781995/2bbdf73e-57a2-11e5-8847-afb709e28495.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781996/2bc90a66-57a2-11e5-9154-6cc3a08a3e93.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782000/2bd232a8-57a2-11e5-8617-eaff327b927f.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781997/2bced964-57a2-11e5-9021-970f1f92608e.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781998/2bd0def8-57a2-11e5-850f-e60701db4f62.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9781999/2bd2551c-57a2-11e5-82e3-54bb80f7c114.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782001/2bdb5bb2-57a2-11e5-8a18-05fe673e2315.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782002/2be52ed0-57a2-11e5-8e12-2f6e17787553.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782003/2bed36de-57a2-11e5-9d4f-7c214e828fe6.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782004/2bef8ed4-57a2-11e5-8949-26e1b80a0ebb.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782005/2bf08622-57a2-11e5-86e2-c5d71ef615e9.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782006/2bf2d968-57a2-11e5-8f44-3cd169219e78.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782007/2bf5e95a-57a2-11e5-9b7a-96f355a5334b.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782008/2c04b458-57a2-11e5-9381-feb4ae365a1d.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782011/2c0e4054-57a2-11e5-89f0-7c91bb0e01a2.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782009/2c0c4254-57a2-11e5-984d-0e44cc762219.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782010/2c0ca730-57a2-11e5-834c-79153b496d44.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782012/2c1277e6-57a2-11e5-862a-ec0c8fad727a.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782122/543bc690-57a3-11e5-83eb-156108681377.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782128/546af1f4-57a3-11e5-8ad6-78527accf642.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782127/546ae2cc-57a3-11e5-9ad5-f0c7157eda5b.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782124/5468528c-57a3-11e5-9cf9-89f763b473b4.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782126/5468cf50-57a3-11e5-9d97-c8fc94e7b9a4.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782125/54687d66-57a3-11e5-860f-c66597fd212c.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782123/545728cc-57a3-11e5-83ab-51462737c19d.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782129/54737694-57a3-11e5-9e1e-b626db67e625.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782130/5483fee2-57a3-11e5-8928-e7706c765016.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782133/54dd0c62-57a3-11e5-85ee-a02c1b9dd223.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782131/54872b30-57a3-11e5-8903-db1f81ea1abb.jpg',
  },
  {
    uri: 'https://cloud.githubusercontent.com/assets/1567433/9782132/548a3b9a-57a3-11e5-8228-8ee523e7809e.jpg',
  },
];

export const PrefetchWithDataCacheData = [
  {
    uri: 'https://placedog.net/300/300?id=122',
    headers: {
      Authorization: 'someAuthToken',
    },
  },
  {
    uri: 'https://placedog.net/300/300?id=123',
  },
  {
    uri: 'https://placedog.net/300/300?id=124',
  },
  {
    uri: 'https://placedog.net/300/300?id=125',
  },
  {
    uri: 'https://placedog.net/300/300?id=126',
  },
];

export const prefetchWithUrlCacheData = [
  {
    uri: 'https://picsum.photos/id/10/300/300',
  },
  {
    uri: 'https://picsum.photos/id/11/300/300',
  },
  {
    uri: 'https://picsum.photos/id/12/300/300',
  },
  {
    uri: 'https://picsum.photos/id/13/300/300',
  },
  {
    uri: 'https://picsum.photos/id/14/300/300',
  },
];

export const liveTextData = [
  {
    url: 'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ejihld4sywvvqwe67cdkn4jq/bafkreibcshvfvfi4suht32tcp4ds77y2yghtcig62byqyq3ot4abpsplhu@jpeg',
  },
  {
    url: 'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:lzlqyldh7nfc34pfffvd24ko/bafkreihimujh4kxa4gecniimqfnmdjnlajjek6pleh5tt5k4djhno3lzu4@jpeg',
  },
];

export const processingData = [
  {
    title: 'Original',
    url: 'https://placedog.net/300/300?id=238',
  },
  {
    title: 'Resize',
    url: 'https://placedog.net/300/300?id=238',
    resize: 150,
  },
  {
    title: 'Monochrome',
    url: 'https://placedog.net/300/300?id=238',
    resize: 150,
    monochrome: 'white',
  },
  {
    title: 'Circle',
    url: 'https://placedog.net/300/300?id=238',
    resize: 150,
    rounded: true,
  },
  {
    title: 'Blur',
    url: 'https://placedog.net/300/300?id=238',
    resize: 150,
    blur: 5,
    rounded: true,
  },
  {
    title: 'Tint',
    url: 'https://placedog.net/300/300?id=238',
    resize: 100,
    blur: 5,
    rounded: true,
    tint: 'black',
  },
];

export const svgData = [
  {
    title: 'SVG',
    url: 'https://upload.wikimedia.org/wikipedia/commons/9/9d/Swift_logo.svg',
  },
];

export const gifData = [
  {
    url: 'https://cloud.githubusercontent.com/assets/1567433/6505557/77ff05ac-c2e7-11e4-9a09-ce5b7995cad0.gif',
  },
  {
    url: 'https://cloud.githubusercontent.com/assets/1567433/6505565/8aa02c90-c2e7-11e4-8127-71df010ca06d.gif',
  },
  {
    url: 'https://cloud.githubusercontent.com/assets/1567433/6505571/a28a6e2e-c2e7-11e4-8161-9f39cc3bb8df.gif',
  },
  {
    url: 'https://cloud.githubusercontent.com/assets/1567433/6505576/b785a8ac-c2e7-11e4-831a-666e2b064b95.gif',
  },
  {
    url: 'https://cloud.githubusercontent.com/assets/1567433/6505579/c88c77ca-c2e7-11e4-88ad-d98c7360602d.gif',
  },
  {
    url: 'https://cloud.githubusercontent.com/assets/1567433/6505595/def06c06-c2e7-11e4-9cdf-d37d28618af0.gif',
  },
  {
    url: 'https://cloud.githubusercontent.com/assets/1567433/6505634/26e5dad2-c2e8-11e4-89c3-3c3a63110ac0.gif',
  },
  {
    url: 'https://cloud.githubusercontent.com/assets/1567433/6505643/42eb3ee8-c2e8-11e4-8666-ac9c8e1dc9b5.gif',
  },
];

export const apngData = [
  {
    title: 'APNG',
    url: 'https://apng.onevcat.com/assets/elephant.png',
  },
];
