# Product Reality

Generated implementation snapshot for product alignment checks.

## Metadata

- generated_at_utc: 2026-03-23T07:07:35Z
- git_commit: 476180add542a1683602429795f22742aa733188
- git_commit_short: 476180add542
- git_dirty: true
- implementation_file_count: 99
- generator: tasks/scripts/run-build-product-reality.sh

## Implementation Snapshot

- dominant_file_types: swift(96), sh(2), js(1)
- dominant_top_level_modules: Hypnograph(87), website(5), scripts(2), SwiftUIPreviewHost(2), HypnographTests(1), HypnogramQuickLookTests(1), HypnogramQuickLook(1)

## Observed Features

| Feature Area | Signal | Evidence Count | Representative Evidence |
|---|---|---:|---|
| Live Playback | strong | 28 | Hypnograph/App/AppCommands.swift; Hypnograph/App/EffectsStudio/State/SourcePlaybackState.swift; Hypnograph/App/Main/ClipHistoryAndLayerActions.swift |
| Effects Engine | strong | 20 | Hypnograph/App/Common/Support/Environment.swift; Hypnograph/App/AppCommands.swift; Hypnograph/App/EffectsStudio/Services/RuntimeEffectsService.swift |
| Session Persistence | strong | 35 | Hypnograph/App/Common/Support/LegacySessionMigration.swift; Hypnograph/App/Main/EffectChainLibraryActions.swift; Hypnograph/App/Main/Live/LivePlayer.swift |
| Recording / Export | strong | 22 | HypnogramQuickLookTests/QuickLookParsingTests.swift; Hypnograph/App/Main/EffectChainLibraryActions.swift; Hypnograph/App/Main/ClipHistoryAndLayerActions.swift |
| Source / Media Input | strong | 43 | Hypnograph/App/Main/Persistence/MainSettings.swift; Hypnograph/App/Common/Support/LegacySessionMigration.swift; Hypnograph/App/Common/Support/Environment.swift |
| Settings / Commands | strong | 37 | Hypnograph/App/AppSettingsStore.swift; Hypnograph/App/Common/Support/Environment.swift; Hypnograph/App/EffectsStudio/Persistence/EffectsStudioSettings.swift |
| Windowing / UI Surfaces | strong | 78 | Hypnograph/App/Common/Support/TooltipManager.swift; Hypnograph/App/Common/Support/KeyboardTextInputContext.swift; Hypnograph/App/Common/Support/Environment.swift |
| Automation / Background | none | 0 | n/a |
| Collaboration / Cloud | light | 2 | website/app.js; Hypnograph/Debug/ExternalMediaLoadHarness.swift |
| AI / Generative Decision | moderate | 3 | Hypnograph/App/Main/Views/AppSettingsView.swift; Hypnograph/App/Main/Views/NoSourcesView.swift; Hypnograph/App/HypnographAppDelegate.swift |

## Implementation Keyword Index

| Token | Count |
|---|---:|
| string | 513 |
| state | 436 |
| main | 411 |
| text | 374 |
| view | 331 |
| name | 323 |
| opacity | 295 |
| font | 287 |
| bool | 277 |
| double | 266 |
| frame | 251 |
| layer | 248 |
| session | 243 |
| effect | 243 |
| label | 236 |
| value | 235 |
| spacing | 230 |
| chain | 222 |
| width | 221 |
| player | 215 |
| button | 212 |
| padding | 211 |
| image | 206 |
| white | 205 |
| alignment | 197 |
| index | 196 |
| some | 185 |
| height | 183 |
| type | 182 |
| settings | 182 |
| window | 177 |
| color | 173 |
| leading | 165 |
| clip | 165 |
| activeplayer | 162 |
| layers | 157 |
| foregroundstyle | 155 |
| effects | 152 |
| vstack | 151 |
| file | 149 |
| source | 148 |
| binding | 147 |
| mark | 145 |
| hstack | 143 |
| size | 138 |
| panel | 137 |
| live | 137 |
| duration | 135 |
| secondary | 134 |
| cornerradius | 134 |
| hypnograph | 132 |
| isempty | 131 |
| system | 128 |
| path | 128 |
| count | 126 |
| data | 120 |
| library | 116 |
| hypnogram | 116 |
| defaults | 116 |
| body | 116 |
| toggle | 115 |
| range | 113 |
| fill | 113 |
| current | 112 |
| forkey | 110 |
| save | 109 |
| weak | 108 |
| style | 107 |
| spacer | 107 |
| context | 106 |
| content | 106 |
| background | 106 |
| volume | 105 |
| foregroundcolor | 103 |
| roundedrectangle | 101 |
| uuid | 100 |
| print | 99 |
| entry | 97 |
| title | 94 |
| settingsstore | 91 |
| void | 90 |
| systemname | 89 |
| device | 87 |
| buttonstyle | 87 |
| show | 86 |
| parameter | 86 |
| liveplayer | 86 |
| param | 85 |
| newvalue | 85 |
| float | 85 |
| caption | 85 |
| seconds | 83 |
| options | 83 |
| mode | 83 |
| shared | 82 |
| selection | 82 |
| mediaclip | 81 |
| json | 81 |
| event | 80 |
| const | 80 |
| action | 80 |
| hypnograms | 79 |
| snapshot | 77 |
| init | 77 |
| failed | 77 |
| coordinator | 77 |
| params | 75 |
| parameters | 75 |
| swiftui | 74 |
| load | 73 |
| isenabled | 73 |
| identifier | 73 |
| foreach | 73 |
| hypnocore | 72 |
| first | 72 |
| transition | 71 |
| swift | 71 |
| flash | 71 |
| effectchain | 71 |
| config | 70 |
| step | 69 |
| chains | 69 |
| model | 68 |
| continuous | 68 |
| slider | 67 |
| mainactor | 67 |
| error | 67 |
| ison | 66 |
| horizontal | 66 |
| global | 66 |
| appnotifications | 66 |
| container | 65 |
| cgfloat | 65 |
| audio | 65 |
| video | 64 |
| design | 64 |
| update | 63 |
| viewbuilder | 62 |
| menu | 62 |
| asset | 62 |
| encode | 61 |
| display | 61 |
| currentsourceindex | 61 |
| time | 60 |
| photos | 60 |
| offset | 60 |
| isselected | 60 |
| weight | 59 |
| published | 59 |
| nsview | 59 |
| monospaced | 59 |
| defaultvalue | 59 |
| overlay | 57 |
| effectmanager | 57 |
| task | 56 |
| status | 56 |
| contains | 55 |
| displayname | 54 |
| vertical | 53 |
| sourceframing | 53 |
| picker | 53 |
| aspectratio | 53 |
| sources | 52 |
| result | 52 |
| observedobject | 52 |
| islivemode | 52 |
| divider | 52 |
| playerview | 51 |
| disabled | 51 |
| append | 51 |
| windowstate | 50 |
| onchange | 50 |
| black | 50 |
| playrate | 49 |
| clear | 49 |
| bounds | 49 |
| tooltip | 48 |
| plain | 48 |
| option | 48 |
| blendmode | 48 |
| nsimage | 47 |
| isexpanded | 47 |
| history | 47 |
| contentview | 47 |
| cgimage | 47 |
| systemimage | 46 |
| filemanager | 46 |
| effectssession | 46 |
| decodeifpresent | 46 |
| rounded | 45 |
| infinity | 45 |
| spec | 44 |
| modifiers | 44 |
| maxwidth | 43 |
| lowerbound | 43 |
| callout | 42 |
| saved | 41 |
| preview | 41 |
| effectindex | 41 |
| currenthypnogramindex | 41 |
| applephotos | 41 |
| appkit | 41 |
| foundation | 40 |
| ciimage | 40 |
| token | 39 |
| encoder | 39 |
| isvisible | 38 |
| existing | 38 |
| enabled | 38 |
| effectsstudioparameterdraft | 38 |
| active | 38 |
| zero | 37 |
| only | 37 |
| mainsettings | 37 |
| loaded | 37 |
| external | 37 |
| bottom | 37 |
| appendingpathcomponent | 37 |
| upperbound | 36 |
| transitionduration | 36 |

## Machine Keyword Set

Use this for alignment matching against implementation reality.

- keyword_set: string state main text view name opacity font bool double frame layer session effect label value spacing chain width player button padding image white alignment index some height type settings window color leading clip activeplayer layers foregroundstyle effects vstack file source binding mark hstack size panel live duration secondary cornerradius hypnograph isempty system path count data library hypnogram defaults body toggle range fill current forkey save weak style spacer context content background volume foregroundcolor roundedrectangle uuid print entry title settingsstore void systemname device buttonstyle show parameter liveplayer param newvalue float caption seconds options mode shared selection mediaclip json event const action hypnograms snapshot init failed coordinator params parameters swiftui load isenabled identifier foreach hypnocore first transition swift flash effectchain config step chains model continuous slider mainactor error ison horizontal global appnotifications container cgfloat audio video design update viewbuilder menu asset encode display currentsourceindex time photos offset isselected weight published nsview monospaced defaultvalue overlay effectmanager task status contains displayname vertical sourceframing picker aspectratio sources result observedobject islivemode divider playerview disabled append windowstate onchange black playrate clear bounds tooltip plain option blendmode nsimage isexpanded history contentview cgimage systemimage filemanager effectssession decodeifpresent rounded infinity spec modifiers maxwidth lowerbound callout saved preview effectindex currenthypnogramindex applephotos appkit foundation ciimage token encoder isvisible existing enabled effectsstudioparameterdraft active zero only mainsettings loaded external bottom appendingpathcomponent upperbound transitionduration store selected ratio parentwindow manifest kind keyboardshortcut hypnographstate historylimit format custom controlsize targetduration small progress date changes trackwidth textview rate output nsapp list files create configuration clipshape build activeeffectmanager trimmed showmanifestpanel showlivecontrolspanel showinspectorpanel showcodepanel rectangle playback metal keys filter wrappedvalue screen minnumber failure extent cmtime cgsize render remove open linewidth info clamped timelineplaybackrate outputsize nswindow maxlayers decode childindex chainindex cancel stroke sourceindex play livevolume hypnographsession upper trailing selectedtab section reset recipe monitor length entries effectdefinitionmockup easeinout defaultnumber atpath activebindings transitiontype showlogoverlay sessionstore pickerstyle outputurl outputresolution none message location framing expandedeffectindices effectdef compilelog available autobind audiodeviceuid visible transitionstyle togglestyle segment scrollview scenario playbackendbehavior parent panelopacity medium medialabel maxnumber lower idleseconds fileexists effecttype effectdefindex code closedrange start snap rendervideosavedestination minlength mediakind labelshidden function down delete appsettingsstore sourcecode semibold runtimeeffectsservice mirror isfavorite intensity folder destination description constraint bordered apply write values trimmingcharacters sourcea sidebar rawvalue radius origin nsevent move monospaceddigit lightbox item equalto environment dispatchqueue directory command colorspace cliplengthmaxseconds appdelegate anycodablevalue transitions targetid specs sourceb preferredlength playerresolution order listselection ispaused help headline favorites effectregistry contentsof contentshape clips choice callback both base auto array whitespacesandnewlines uint thumb select outputfolder next manual linelimit fileurl disk defaultbool decoder composition cicontext chevron borderless blue audiocontroller arrow anyview viewmodel types success stop sourceplaybackservice root resolution preferredtimescale playeritem ontapgesture normalizedpath normal jpeg focus effectsstudioparametermodeling edge currently compact cliplengthminseconds square response removeall onchanged notificationcenter metalrenderservice maxheight loading livemodeenabled liveaudiodeviceuid keyboardaccessibilityoverridesenabled isdirectory hypnogramlayer hypno field effectslistcollapsed document currenthypnogram createdat controls activelibraries accentcolor trackheight total targetsize support span sourcemediatypes sessionurl selectedruntimetype right random primary playercontentview pause observer object normalized magnitude level insert generator focusedfield enumerated edit docs aspect target studio sorted snapshotsfolder sink single shift role returns recent randomlayereffectfrequency randomlayereffect randomglobaleffectfrequency randomglobaleffect minwidth member initialvalue header fileid encoded effectchains effectchainmockup draft control clipplayratemin clipplayratemax clean caption2 blueprint based appsettings textvalue sync starttime startpoint slot scale sample replace renderqueue plus playerconfiguration pipelineerror parameterspecmockup outgoing onselection notification liveaudiodevice lineargradient lastpathcomponent isediting images identifiers icon favorite endpoint effectsstudiosettingsstore disablemainwindowshortcuts direction combined colors codingkeys circle choiceoptions center capsule bold animation zstack withanimation wire whether ultrathinmaterial thumbsize texture stringvalue stepper stateobject slow send rootview restore renderengine queue persistence pending parameterspec override notifysessionmutated merge managed loop libraries ispresented hypnogramentry glass fixedsize escaping echo during detail check blend appsupportdirectory application apple advance activeslot activeavplayer withintermediatedirectories windows which timeout thumbnails thumbnailbase64 textfield starthiddenonenable sourceid shader setvalue requestplan polltimer pipelinestate photo phase observableobject mockup mainwindow liquid istyping ishovering intvalue hypnogramstore green frequency firstindex effectsstudioviewmodel effectsstudiosettings destructive createdirectory codable checkbox changed bundledurl basename availableeffecttypes audiodevice totalseconds thumbnailstore textfieldstyle tertiary template still solo runtime players playerconfig persist onappear objectwillchange nscolor mindistance localizeddescription layout layerindex lastsourcevalue last isfinite hypnoui hidden framerate ensure effectsstudioenabled defaultchoicekey convenience cliplength backward avfoundation applyclipselectionchanged activityignorerightinset activityignoreleftinset writer version urls transitionrenderer trailinganchor timestamp timeinterval thumbnail standard specific speaker sourcecount slidervalue separator scaled required removeitem persisted paths parameterbufferindex ontoggleexpanded nextsource maxwindow lowercased local livemode left leadinganchor lastsourcekind jsondecoder items issues ismuted isautoadvanceinflight install input injected hostservice hide fromindex favoritedat expanded exclusionstore editing dropinfo dropfirst doublevalue dependencies defaultkey customphotosassetids currentindex currentclip coremedia contentmode compositionid cache base64 backgroundcolor appendchild access visibletooltiptext uttype uint64 topleading topanchor subtitle showinitialstatus shadow setvolume sessionrevision selectsource selectionlimit same proxy preselectedidentifiers prefix point parameterspecs panels outgoingslot otherwise ondelete navigation named media manager lastmovetime lastmouselocation inputtextures infolabel indicator incoming generation frameindex fallback export expect effectsstudiochoiceoption effectslibrarysession dragmode draftrange detailoverride delegate defaultvisible dateformatter createelement completion breadcrumbel bottomanchor bloomeffect avplayer avasset audiomanager archive activelibrarykeys will visibletooltipcontrolid uuidstring usablewidth updatecurrenthypnogram totalvideoseconds tooltipmanager targetscreen stillcliptimer statustoken startx sourceover sleep setflashsolo selectedlayerindex saving safetotalseconds resizable rendererview randomize playerslot playercontent parameterbufferlayout onclipended nsstring nssize nsscreen node nanoseconds muted mediatype mainwindowfullscreen loadedsource lastrenderedclip keyedby keydown keep jsonencoder isallstillimages initial imageview identifiable hudtooltip huditem hold helpers have haschain handle full forward focused effectdefinition discardableresult deviceuid defer currentframe created coreimage compile combine cliphistoryfile candidates buttons boolvalue backupurl audiooutputdevice atomic allowedcontenttypes allcases xmark valid utf8 uses trash track toindex tint timer texturewidth textureheight textcontent teardown styles sourcevideoasset shows screens removeobserver regular register refresh quaternary previous previewsize playersubscriptions playerstate placeholder pendingbuildtask parameterbuffer onload oncommit nsviewrepresentable normalizedtimelineplaybackrate missing minimumdistance mainsettingsstore link keyboard invalid immediately hasexternalmonitor generated fullscreen found foruuid forname formatter formateffecttype fixedlower finder favorited exists endx encoding effectschangecounter effectlist effectiverate duplicate draggingeffectindex disable didrequestpreendadvance deck cropped copy cliptrimcontext cleanname cfabsolutetimegetcurrent canread candidate bytes bundled buffer bottomtrailing behavior back autoadvanceonclipend arguments always alert addobserver activebackground videos updatensview updatedchain typename triggers tree togglecleanscreen timeseconds timelineplaybackcontrolvalue templateid templatedisplayname tempdirectory summary subscriptions startseconds staging space sourcestillimage snappedval simulate sidebars showphotospicker setglobaleffectsuspended sequence segmented schema savesnapshotimage sanitizedchoiceoptions runtimemetalparameterschemaentry runtimeeffects runmodal runloop replacingoccurrences relativepath registry recentstore properties products previewframehistory parts parametervalues outgoingslotduringtransition onselect onduplicate nsrect nsopenpanel nexttime nextindex never minwindow minvalue mergedparams members maxvalue material matching makensview makecoordinator lowerpercent lines line latch lastexternalvalue language keyboardhint istextfieldfocused isplaying ismainwindowshortcutcontext isint invalidate indices ignoressafearea idle hasprefix fileurls filename exportsession excluded endseconds empty embedded effectname effectchainlibraryactions each documentel dist details descriptor delta defaultmontage darkmodeswitchstyle currentlayer convert contextmenu compactmap choose cgcolorspacecreatedevicergb caseiterable bundle built avplayerframesource avoid attributes applytemplate applyaudiomix allowsmultipleselection activerange activate 1080p your visual updates unnamed uniformtypeidentifiers transitionstateprovider tracks title2 timelineduration super suffix styling sourcetemplateid sourcefavoritesstore simulated showeffectsstudiochrome shouldhandlekeyboardoverride shouldhandleevent settingsurl sender selectedchaincontext segmenturls segments runtimemetaleffectmanifest runtimelibrary routevalue roundedborder rightsidebar restored resolver resolvedchoicedefaultkey resetpreviewhistory renderpreview rendered renametargetid radial previewimage prevent prettyprinted position playratebounds playercontentmirrorview persistentstore parametername panelsize overflow outputformatting orange optional openincomingfiles ontabpressed onsubmit onremove onended older observers newupper newlower newid mouselocation modifierflags mirrorviews mirrors minv mini minheight mediafile maxdimension loren localidentifier loadifneeded light leftsidebar lastpausestate keywindow keymonitor jpegdata joined johnson istimelineplaybackreverse issololatched ispressed ismodalrunning intersection hypnogramquicklook hypnocorehooks host home hljs historyplaybackrate handles general force folders fixedupper find externalmedialoadharness explicit enable effectsstudiopanelhostservice effectsstudio effectfunctionname draggesture draggedlayerid draggedchainid didset devices deviceindependentflagsmask defaultsettings decoded deckbutton dark cyan cursor crossfade coreconfig controlid contentframe constant commandqueue close cliphistorystore click clampedstart clampedend chromaticaberrationeffect checker cgrect borderedprominent attempts applied applications applephotoslibrarykeys allplayers addsource addlocalmonitorforevents activelayercount workitem windowsize windowid windowbelongstomain visibility variations valuetype value3 value2 value1 user upperpercent updatedownloadprogress unified truncationmode translatesautoresizingmaskintoconstraints transitiontoken transformed togglelibrary targets targetlength tabiconbutton systemparameterblueprints suspend subscription startifneeded stack speed sortedkeys snapshotbase64 sliderrange slash showrightsidebar showleftsidebar showing setup setter seteffectenabled secs runtimemetaleffectlibrary runtimemetalbindingsmanifest runtimeeffectname reveal responder resources resource reseteffecttodefaults replacing replaceclip renders refreshstatus refreshruntimeeffectlist rect receive rawsegments primarysource previousid preserveexisting playbacktask phpickerviewcontroller photoscustom pendingtooltipworkitem pathname pathextension parsedindex paramtype paneltogglebutton outputtextureindex onphotosauthorization null nstextview nextslot newrange newname needed movies minupper mins metalrenderserviceerror menustyle mediasource maxv maxlower maxdurationseconds manifestcontent manages makekeyandorderfront macos looping loopcurrentclip logentries loadrandomsource livewindow livepreview livecontrolscontent limit layerdatamockup lastvideoframeimage lastappliedplayrate just jsonserialization istimelinereverse issystemparametername isloopcurrentclipenabled islivemodeavailable islibraryactive iscleanscreen iscancelled isarepeat invalidatevideoframecache inspectorcontent inputtexture inline incomingeffectmanager imageduration identity hover hascontent globaleffectchain gesture geometryreader fromtypename fraction forsourceindex formattime fontweight float2 filtered exportqueue expandedlayerids equatable ensuresettingsfileexists endswith effectsstudioscalarvaluetype effectsstudioparambufferlayout effectsstudioautobind effectslistselection effectivevideoplaybackrate edited durationseconds dropproposal dragstartrange draggingindex drag docstreeel displaystring displays dirs directoryurl dict dest deletinglastpathcomponent deadline dataset currentvalue currentsourcetime currentrecipedescription currentcliptimeoffset counter couldn coregraphics configure concatfailed components compileresult commandgroup collaborators codingkey codecontent cicolor char change canchoosefiles canchoosedirectories borderlessbutton basepath backgrounds backed authorization asyncafter assets applyactivelibrariesunified appearance alpha advanced addsubview addsourcetoplayer activekeys zindex xposition writescalar workflow withmediatype watch wantslayer vintage viewid videoframegenerator valuetext updatetimelinedurationfromcurrentsource updateeffectparameter updated updatechainname unsaved truth trigger translationx trailinghandle tracking totaldurationseconds toggleplaypause togglelivemode thumbnailsize thumbdiameter threadwidth targetwidth targetheight tapgesture syncpanel synchronous symlinkurl stylemask storeurl storage states split snapshots snappoints skip simultaneousgesture sidebarmetrics short sheet shadersource setaudiooutputdevice setattribute sessionsdirectory selectedwidth seek sectiontitle script scheme scalex scaledimage saveaudiosettings sanitized runtimeeffectversion runtimeeffectuuid runtimeeffectdirectoryurl routepath rightdistance reverse resolveddocpath repeats repaired renderedurl rename removeeffectfromchain removeduplicates refreshavailablelibraries rebuildparametervalues real ready randomization quick provides provided proposedvalue prevents playimmediately performdrop pendingparameterscrolltarget pendingincomingfiles pattern paramname parametersliderrow panelwindowsurface panelhostservice outputtexture opentreepaths onsave onrename onhover onclose nsworkspace nsobjectprotocol nslog nslayoutconstraint nsapplication notify normalizedeffectuuid nonisolated mtldevice movelayer modifying modes mirrorview minsize minimumduration metalcontent mediasourcesparam materialsample management maketexture makeclip localx loadruntimeeffectasset loadphotossource loadfilesource livecontrols liquidglassdivider liquidglass like less leftdistance leadinghandle lazyvstack layerchain lastvisibleopacity lastsettooltip lastplaybacktickuptimens lastaudiodeviceuid keycode jsonobject istransitioning istimelinespeedactive issupportedextension issidebaropen isrequestingphotos isplayercontrolsvisible ishiddenbyus isfullscreen isfirstload isfillwindow instead inputsourcelabel indicators independent includes ignored hypnoparams hypnographappdelegate homedir hideallpanels helper handled globalchain getelementbyid geometry framesource forseconds fileurlwithpath fetchasset fallbackbase fall extract externalloadharness expectedtextureindices expandedchainids expand enter engine ends effectuuid effectsstudioparamtype effectsstudiopanelkind effectsstudiodependencies effectseditorviewmodel effectseditorhoverrevealcontrolsrow effectseditorfield editableparameterdefinitions editablelayer duplicatedlayer downloading divisions ditto displayresolution dirname directorypath didbecomemainobserver didbecomekeyobserver dice diameter deletetargetid deleted deinit defindex defaultparameters defaultcodebody datatype cycle currentvolume currenttooltip currenttask currentfileid crossfadeduration createcgimage controller computed completes compilecode compatible common commandbuffer column closeobserver clone cliptrimcontexts clipped cliplengthseconds cliplengthrange cleartask cleanscreensnapshot classlist clampedseconds clampedbase checksum chance chainsummary chaindisplayname cgpoint cgcolor card cacheorder cached buttontitle begin availablelibraries automatically autoadvance atrate aspectfill apps anycancellable angle also addeventlistener addeffecttochain activewindowcontext activethumb activerequiredlookback activerequesttokens writes writerstartfailed writerfailed wrapper workingcolorspace workflowname withtimeinterval windowstatefileurl wave vignetteeffect videoframegeneratorassetid videoasset usegeneratedsample usage untitled until unknown unhideifneeded uint32 truncatingremainder triggerautoadvance transport translation totaleffects totalduration tooltipbubble tools toggles togglepause toggleloopcurrentclipmode togglefullscreen titlevisibility titlecasesegment title3 timelineaccentcolor timeline tiffdata thumbnailview threadheight textfieldfocusmonitor test templates tabs tabmonitor systemdefault synctransitionstate syncfromsession switching suspended startpollingifneeded startlocation starting stablejsonencoder sourceplaybackloaderror sourceframingbuttons sourcefile sort snapshotdata slice simulatetimeout simulateslow simulateprogress simulatefailure showterminalstatusandclear shown showaddlayerphotospicker shouldrestoremainwindowfullscreenstate shortframinglabel shortcuts shortaspectratiolabel shaderurl setupeffectssession setupeffectmanager settingstogglerow settingsactionrow setmainwindowfullscreenstate setloopcurrentclipmode seteffectmanager setcontentmode sessionfileactions sessioncancellable sequencefailureslownormalfailurenormal selectedratio selectedrangeseconds selectedindex selecteddevice segmentpath seektostartandplayifneeded seed sectiondivider searchtext scheduledtimer scaledextent scalartype scalarsize savetodefaultlibrary saveruntimeeffectasset savelibrarytofile saveas sampletimeseconds sampletime samplerlinear runtimeparameterentry runtimeeffectsdirectoryurl routing rightsidebartab resume restoredefaultlibrary resolvemainwindow resolveexternalvideo resized requestmainwindowfocus request representation repo replacehistorywithnewclip repair rendersize rendering renderhypnogram renametext removefirst registermainwindow regex reflection recording recenteffectsstore rebuilt reason randomclip queryselector prompt project previousvolumebeforemute previoussource preservingglobaleffectfrom precision positive pollonce plist playratemin playing playbacktimeobservers playbackendobservers photosvideoloadfailed photospickersheet photoslibraries photosfilename persistlastphotossource persistlastfilesource persistedsourcekind pendingselection pendingphotosauthorizationcallback pencil paused parsed parentcloseobserver parameterdrafts parameterdefinitiondidchange p1080 outputimage outputdirectory outputdevices outgoingclip originallevel originalfilename orderedsame openwindow ontransitionprogress onreorder ondrop ondrag once numberfield nspoint nsitemprovider nsbitmapimagerep notifysessionchanged notifymirrors note newpercent names mute mutablesession mtltexture movechain mouse module modifier modal missingoutputimage minutes minimumwindowseconds metaltype metalcodeeditorview mergecheckbox menus medialibrarybuilder maxindex manifesturl managedpanel makerandomclip makefirstresponder makedisplaysession mainwindowfullscreenobservers look localstorage localizederror loadtask loadmediaclip loadlibraryfromfile loadandtransition libs legacysessionmigration legacy layerlabel layereffectchain launch lastvolume lastsessionrevision lasteffectscounter keyup keeps iswindowvisible isvalididentifier issoloactive issolo isshifttab isplaintab iskeyboardtextinputactive ishomepage isglobaleffectsuspended iseffectsstudiowindow isautobound isapplyingstoredeffectsstudiouistate instant installed insertionrequest insertion innerhtml initialize inflight importedcount imported imageurl idealwidth hypnogramlist hypnocoreconfig hudview huditems hovering homelink homedirectoryforcurrentuser headerrow hashable handlewidth handletooltiphover handlehitwidth glow globe globaleffectname glasspanel glassdivider generatedsource gaussianblureffect frozenmanager framecounter framecount folderurl folderlibraries focusstate focusable float4 flag finished film fileprivate fileextensions failedcount expandingtildeinpath expandedpath exit exclude eventwindow errordescription equals ensuresystemparameters ensuremodalpresentation enforcehistorylimit endobserver encodeifpresent embed elapsed effectsstudiotabkeymonitorservice effectsstudioparambuffermemberlayout effectslistsectionheader effectparameterrowview effectnotfound effectivetransition effectdropdelegate effectcount editedname dropdown download doesn docssidebartoggleel dividingby dispatchworkitem dismantlensview diskandphotosifavailable directly direct didloadeffectsstudiouistate didinitialload didconvertany didapplymainwindowfullscreenrestore detachfromcurrentparent deleteruntimeeffectasset defaultsourcelibrarykey defaultsize defaultmainsettingsurl decimal darkmodecheckboxstyle cycleeffect currenttime currentsourceimage currentframesnapshot currentaudiodeviceuid creationdatekey creationdate createmirrorview counts core copyforexport copycgimage coordinate contexts contentfocus complete comp commands colorinverteffect collectionbehavior coder clipminbinding cliphistoryindicatortext cleartogeneratedsamplesource clearframebuffer cleareffect cleared cifilter child cgcolorspace cftimeinterval caseinsensitivecompare canwrite canonicalchoicevalue called callbacks cachesize bytecount building boundtextures bloom blendmodes bitmaprep bitmap bindir backupname backing avurlasset avassetimagegenerator automatic autocompile aspectratiobuttons artifact aria argumentindex applyloadedvideoasset applyloadedstillimage appendsessiontohistory appdir already allowshittesting allitems addtemplate adds addingtimeinterval added actualtime activeusespersistentstate activetransition activetextureindices activesequenceindex activesection activeruntimekind activeframesource activatefileviewerselecting above yellow writesettings writecodablesettings withtitle withextension wired windowwidth windowed windowbelongstostudio wide whole weakmirrorref watchmode volumebeforemute viewmodifier validationproblems uturn utility uppert updateparameter unsupportedphotosassettype unsupportedfiletype unsigned uniquename unavailable typing trymakeresizable trimmedbase trimhandle treated treatasdouble transitioning tolerancebefore toleranceafter togglerightsidebar togglemediatype toggleleftsidebar toggleeffectsstudiocleanscreen timing thumbradius thumboffset thumbnailfromavasset texsize testing testimageerror tail symlink surface subtle subheadline structure stored storagepath stillimagecache stepped stepindex steal starts star stall sourcewidth sourcelibraryorder sourceheight sourceeffectchainsetter soft snapshotsurl snapshotlayer smaller slotsource sliderstep sliders sliderrow simulationmode signing signaturemismatch showtimelinespeedpopover showsettingsfolderinfinder showrestoreconfirmation showdeleteconfirm showcontrols showchrome shouldopen shouldmerge shouldapplyrandomizedeffect shasum shares sharedrenderer settooltip settingstabbutton settingstab settingsfolderrow settingsdevicerow setlayercliprange setcustomphotosassets setcontentfocus setaudiodevice sessionwithsnapshot sepiaeffect separate selectsourceindex selectgloballayer selectedphotosidentifier selectedid segmentrenderfailed segmentrange segmentmissingvideotrack segmentlabel segmentduration seenkeys seen search scrollto schedulestillcliptimer schedulecliphistorysave scaledtofill savewindowstatetodisk savewindowstate saveeffectsessions savecliphistory saveandclose sanitize runtimevalue runtimemanifestfromcurrentstate runtimeeffectsserviceerror runtimeeffectchoice running rows rippleeffect rightwidth rightsidebarmockup rewrite reusable results responsive resourcevalues resolveexternalimage resolvedoptions resolvedintvalue resolvedhistoryoffset resolve resettotemplate reservecapacity requesting replaces replacecurrentitem replacechains reordereffectsinchain renderresult renderer renderedsegmenturl renderdocstreenode renderandsavevideo renamed removeplaybacktimeobservers removeplaybackendobservers removeparentcloseobserver removecurrentlayer reload regularphotoslibraries registers registering refreshphotoslibrariesafterauthorization refreshactiveframe recipeurl recententry recenteffectchainsstore rebuild reads read reactivity rangesliderview rangeslider randomvideoloadfailed randomtemplatechain randomizelayereffects randomizeglobaleffect randomizeeffectparameters randomizeeffect randomizationrow randomimageloadfailed queueautocompile queryselectorall push prominent priority previousindex previousclip previewvolume preserveglobaleffect present prefer posixpermissions popover playratemax playermodebutton playerb playera pixellateeffect pixelbufferpoolunavailable pixelbufferpool pixelbufferout pixelbuffercreatefailed pixelbuffer pipeline pick photosimageloadfailed photosifavailableotherwisedisk photosauthorizationdidcomplete photosassetmissing photosaccessdenied persistsource persisteffectsstudiouistate persistedwindowstate permission pendingcodeinsertion pausing partial parse parentpath parentframe paramspec paramsbytes parametertext parameterlist parameterentries parameterdefault parameterbufferbytes panelcard overwrite outputsettings originaldata orderout ordered operation opens opening opened onuserinteraction ontoggleloopcurrentclipmode ontogglefavorite onsnapshotcurrent onsavecurrent onrendercurrent onprevious onplaypause onnext onloaded oninsert onfailure ondisappear oncommitcliptrimrange onapplytoselectedlayer offsetuv offsetpixels numericslider numeric nsrange nsobject notsetsentinel noiseeffect nextlayer nextclip newval newtooltip newkey newcount negative mutation multilinetextalignment mtlcomputepipelinestate monitors mixed missingparameterbufferlayout minx minimumwidth middle metaldevice metadata messagetext mergedparametersforeffect merged menupresets menulabel menuindicator mediaurls medialibrary maxwindowseconds maxtime maxselectiondurationseconds maxselection maximumwidth materialized match markdown manifestjson maketabkeymonitorservice makepanelhostservice makegeneratedpreviewimage makecontext makebody lowerx lowert localecompare loads loadedruntimeeffectasset loadedhypnograms loadedcustomids loaddocstree loaddoc livepreviewpanel liveplayerscreen livecontentviewwrapper linear librarychain leftwidth leftsidebarmockup leftboundary layerthumbnailstore layereffectfrequency layercount lasttext lastsourcekeyindex lastsourcekeydowntime lastphotosstatus keyboardhints istypingactive istextediting isreleasedwhenclosed isopaque isongloballayer iso8601dateformatter isnamefocused ismediatypeactive iskeyboardaccessibilityoverridesenabled isinstalled ishovered isdestructive iscollapsible isactive insertindex inout initializefromvalue infotext infer include immediate imagedecodefailed ignoringotherapps ignore iframe icloud hypnogramlistview hypnogramlisttab hypnogramindex hueshifteffect href homepath historyoffset highlight here hasunsavedeffectchanges hassuffix hasregistered hasappliedinitialruntimeselection handleupdown gradient globaleffectfrequency globaleffectchainsetter given getattribute generating fresh freezeactivesloteffects freeze frames framerect forresource formattimelinerate formattedtimelineplaybackrate formateffecttypename forkeys forfileurl focusmainwindownow focuseffectsstudiohostwindow flags finishwriting findaudiodevice filenameextension feedback feature fading extracteffectchains extra expandedeffectindicesbychainid exist execute example events escape equivalents ensurecontentview enqueue ended encoderuntimemanifestjson enableeffects emptyview emptyselection effectsstudioview effectsstudiouipanelstate effectsstudiotogglecleanscreen effectsstudioruntimeeffectchoice effectsstudioparameterdefinitionrow effectsstudiocleanscreensnapshot effectsstudiochildpanel effectseditorview effectmanagerb effectmanagera effectfunctionnotfound effectdefinitionrowmockup effectconfigloader effectcheckbox effectchainview effectchainsectionmockup edits editor editableparameternames editableeffectnameheader edgegrabtolerance easeout duplicatetemplate dropupdated dropexited dropentered dropdelegate divine displayedconfig displayed diskonly disconnected didsessionmutate didnotifymirrorsfortransitionstart dideffectschange dictionary determine derived depth delayedliveloadingtask defaultruntimebindings defaultfilename defaulteffectsstudiosettingsurl defaultappsettingsurl deep decodedsession deckbarbuttonstyle debug darkmodeswitchcompact cycleblendmode customselectionfileurl customcount cursorautohideview currentwidth currenttargets currentsource currentparent currentlibrarykey currentitem currenthex currentcliptext curatecurrentsource cumulativepath creating creates counterclockwise corrupt copyitem continuation contenttypes contentrect consume configuredplayratemin configuredplayratemax configured concatexportsessionunavailable concatenate compressionfactor component completionhandler compilegeneration compatibility compacttextfield committed commandmenu colorpicker collisionindex collectmarkdownpaths collapsed collapse codesign clipmaxbinding cliplengthmin cliplabel cliphistoryurl cliphistorysavetimer cliphistorysavecancellables cliphistoryindicatorclearworkitem clearslot clearmainwindowfullscreenobservers clearing clearcontent classname clampedwidth clampedlower cioutput checkmark cgaffinetransform canreadphotos cannot canceltransition cancelled canbecomemain call byuid buildandtransitionmetal buffered bufferarg border blureffect blendmodename bindings better bash basevolume basevideoresolver baseimageresolver baseimage base64encodedstring base64encoded avplayeritem availablelibrarychains autosavename autoresizingmask automator autoboundparametersummaries autobound audiotrack audiodevices audiodevicerow audiodevicemanager assetid args appropriate applystoredmainwindowfullscreenpreferenceifneeded applysidebaropenstate applyrecententry applyeffectmanager appliespreferredtracktransform appendnewclipandselect appendlogentry appcommands anycodablevaluemockup another anchor allowedtypes allow addeffectmenucontent addbutton adaptor actually actual activesequencescenario activescenario actions accessors accessibility yyyymmdd xcodebuild wrote writing wraps works workaround work withunsafebytes windowresizer windowregistrationmodifier windowgroup windowframe windowbackgroundcolor willclosenotification widthratio whitespaces waiting volumes visually videotrack videoson videoframe videoexts versiontext variants validtypes validatesignature validateparameterdrafts usespersistentstate usesnumericrange userservicesdirectory users userconfigurl url2 url1 uptimenanoseconds upperx uppercased updaterange updateplaybackloop updateopentreepath updatelocalchain updatelibraryentry updatecontrolparameter unsupported unmute uniquetemplatename unexpected unable uipanelstate twirleffect trim triggered triangle treat transparent transitionstyles transformsstr transform totalframes torelativedocpath toptrailing toprightindicatorbadge toprightindicator topbar tooltips tooltipdelay toolsdirectory tonearest togglevisibility togglevariationsmockup togglemute togglefavorite toggleexpanded toggleeffectexpanded togglecleanscreenforactivewindow toggle4 toggle3 toggle2 toggle1 titlebarappearstransparent timezone timestyle timelinespeedpopover timelinespeedbutton timelinespeedbadge timelinerate timelineplaybackdirection timelinecontrolvalue timedomain tilewidth tiffrepresentation tickmarks tickdurationns tick thumbnailtrack thumbnailimage thumbnailfromurl thumbnailfromexternal threshold threadspergroup threadgroups thread thin textureargs texture2ddescriptor texture2d textfieldvariationsmockup textcolor text2 text1 tests terminatenow temporarydirectory teal tabkeymonitor synced switcher swiftuipreviewhostapp swiftuipreviewhost swiftuicolor supports successfully succeeds succeeded subtracting subtitlewithblend subtitlebase subsequent subscribe styled studiowindow strval structtype strokeborder stripfrontmatter stores storeincache stopmodal steppervariationsmockup steppedrate stem statusfooter startswith startindex stale stableid stable srgb spurious specified spacekeymonitor sourcevideotrack sourcesmenu sourcesany sourcemenu sourcelibraryinfo sourcelibraries sourcekeymonitor sourcekeycodes sourceframingoptions sourcecurationaction sourcecontainshypnoparamsstruct sourceaudiotrack sortedfiles sorteddirs snapthreshold snapshotwidth snapshotkeymonitor snapshotjpegquality snapshotimage snapshotheight snappedvalue smooth slidervariationsmockup skipped sizes simultaneously simulation signprefix signed signatureerror sign sidebarkeymonitor shuffle showliveloadingifneeded shouldtreatintasdouble shouldplay shouldmigratesessionjson shouldhandleeffectsstudiotab shouldenableloop shouldautohidecursor shouldadvanceonclipend shortversion shortenedpath shortdatetime shortcut sharing shaderwrite shaderread setupvideolightboxes setupsubscriptions setupsessionsubscription setupplaybackendhandling setuplooping setupcliphistorypersistence settingswindowpresentationconfigurator settingsstepperrow settingssidebarcontent settingsrenderdestinationrow setting setsourceframing setoutputresolution setmainwindowfullscreen setitem setinterval setattributes setaspectratio sessionurls sessiontypes sessionfile services sequenceplayerconfig sendtoliveplayer sendevent semi selection3 selection2 selection1 selectedurl selectedplayrate selectedpaths selectedidentifier selectedeffectindex selectedduration segmentbaseurl secondsdelta secondarysource scrollviewreader scene scaley savevideo savesidebaropenstate saves saveopentreepaths savedeffectchain savecustomselectiontodisk sampleseconds safesliderstep runtimemetaltexturebindingmanifest runtimekind runtimeintdouble runtimeeffectpicker runtimedouble runaway routepathfordoc ring rightsidebarview rightboundary rightarrow rgba8unorm rgba8 rewrites revealsource reuse restoreinitialsource restorecliphistory restarting resolving resolveselectedsourceindexforcuration resolvedparametervalue resolvedocpath resolved resolveasset resettodefault requiredlookback requestphotosaccess requestedtimetolerancebefore requestedtimetoleranceafter requestedtime requested requestauthorization represents replacecurrentclipwithnewclip replaceclipforcurrentsource repairsettingsfile repaireddata renderbreadcrumb removing removevalue removetimeobserver removeparameter removemonitor removefromindex removedkey removedid removechildwindow removeattribute remainingvideoseconds remainingrealseconds remaining remainder release registration registerwindow registered refreshavailableruntimeeffects redshifted redraw recordingoutputurl recipes recentvarianttext recentsection recentrow received rebuilds rebuildlibrary reasonable readme rangeslidermockup randomvalue randomtemplates randomseed randomrate randomly randomizing randomizechainparameters quicklookparsingtests quicklook quality qlpreviewingcontroller provider proposedt proposedlower progressview process previoussnappoint previouskey previewviewcontroller previewhistorylimit previewhistoryimage previewdevice previewbackdrop previewaspectratio press preset preservetemporalstate preservekeyframes preserve presentationtime preparing preferredtrackid post points plistbuddy playraterangerow playratecontrol playpausesystemname playpausebutton playersettingsview playercontrolsoverlay playercontrolsbar playbuttonbackgroundcolor pixelformat pixelbufferattributes pixel pipefail pickervariationsmockup phpickerrepresentable photosui photosbuttontitle phassetresource persistlastsourcesample perms pass paramseditor paramkeys parametervalue parametersforchainreadonly parametersforchain parameterscolumn parameterrow parameterorder parameternames parameterfieldsforeffectreadonly parameterfieldsforeffect parameterdefinitionsection parameterbinding pairs pairedvideo p720 outputarg outgoingvolume orderfront orderedascending optionally optimized opposite opensession openrecipe openbuttons onstatusmessage onsaved onreloaded onkeypress onchoose onchainupdated onapplytoglobal oldcount ofitematpath offsets offsetamount observemainwindowfullscreen objectidentifier number nsviewcontroller nsscrollview nssavepanel nsregularexpression nspanel nshostingcontroller nscursor nscoder nosourcesview normalizedposition normalizedhistoryplaybackrate normalizedeffectversion normalizedeffectname normalizeddata normalizedbase normalize nextsnappoint nextparametername nextchoicekey newwidth newuid newtype newsession newrandomclip newperms newly newkeys newitem newindex newheight newfield newest newduration newcolor newchains newchain nestedprefix nestedfiles nesteddirectory need namefieldstringvalue mutablevalue mutable multiply multiplier mtltexturedescriptor mtlsize mtldatatype mtlcommandqueue mtlargument movie moveitem movedlayer moved mouseidlevisibilityview more montageplayerconfig models modalwindow modalpanel mockups mockupparameterspecs mkdir mipmapped minlower minimumdurationseconds migratesessionfileifneeded migratedkeyboardoverride migrated memory means maxy maxupper maxticks maxsourcesfornew maxselectionforclip maximumsize maxcacheentries maxbindingoffset marks markdownutils markdownit manifestpreviewjson manifestpanelcontent manifestinspectorsection manifestdata managers makeviewmodel maketransitionsnapshotmanager makesnapshotdata makes makeplayeritem makedisplayview make maintains magnitudestring machine luts lutname luteffect lookups lonsuffix longitude logoverlay locationstring locate localizedcaseinsensitivecompare locale loadwindowstatefromdisk loadstatus loadsidebaropenstate loadsession loadopentreepaths loadfromjson loadfromhypnogram loadcustomselectionfromdisk loadcodesource loadaudiosettings liveindicatordelaynanoseconds livedevice livecontrolssection livecontrolspanelcontent lists listcolumnwidth links lightboxes libraryrow librarychains librariessection libexec leftsidebarview leftarrow layertitle layerstabmockup layerrowview layerrowmockup layerreorderdropdelegate layered launches latsuffix latitude latest latched large landscape labeledsliderrow keyboardtextinputcontext keyboardhintbar keyboardaccessibilityoverridefrommainsettings kernel kept kcmpersistenttrackid kciinputimagekey kciinputbackgroundimagekey jsonparams joinurlpath join itself isvalid istypinginkeyormainwindow istab issystemdefault isopen isinsideactivityregion ishidden isfileurl iseditable isdown isdoubletap iscustomactive isat100 isarray interval int32 instances installparentcloseobserver installhookwrappersifneeded installcli installautomatorquickaction inspectorpanelcontent insideselectedrange inserttimerange insertparameterusage inputcolor1 inputcolor0 inputcenter inner initializevalues initialization individual incomingvolume incomingslot including inactivity importedclip importchainsfromsession implemented implementation imageson imageexts idlefor identical iconname hypnographtests hypnogramrowview hudtooltipmodifier http holds hittransparentview historytexture historyspeed historyimage historyframe hints higher high hidesondeactivate hides hideifneeded hiddenmodechanged hhmmss held heightratio heightanchor hdiutil hasvideotrack hasvideo hasanyvisibleoverlay hard handling handlewindowwillclose handlerenderedvideodestination handleparentwillclose handledevicelistchange group graphics globalsection globalkeymonitor globalexpanded globaleffectchainrowmockup globaleffect glitchblockseffect getitem generatethumbnails generatethumbnail generatedparamstructsource generalsettingsrows gearshape future fullscreenprimary fullscreenauxiliary fulllayoutmockup frozenclip frontmatterpattern fromrate fromphotosassetidentifier fromfileurls fromfileurl fromcontrolvalue freezeoutgoingeffectsifneeded framingpart frameduration framedifferenceeffect fortranslationx forphotosassetidentifier formode formattedtimelineplaybackratecompact formattedduration formattedcliplength formatcamelcase forinfodictionarykey folderkeys focussection focuseffectdisabled flows floor floating float3 flashsoloindex flashcliphistoryindicator fittedimage fittedciimage firstmatch firstlayer fires fire filtername filtereddata fillparameterbuffer filepicker filepath fileextension fields fetchdirectorylisting fetch favoritespopovermockup favoriterowmockup favoritecurrentsource favoritecurrenthypnogram fatalerror fast failurenotification failedtowriteimage failedtocreatecgimage fail externally externalloadstatusbadge extensions exportsettings explicitly expected expandedcontent expandable existingcontent exclusionsurl exclusions excludecurrentsource except even erratic entire entering ensurevideosegment ensurepanel ensuredvideourl ensuredefaultsettingsfilesexist ensuredefaultmainsettingsfileexists ensuredefaulteffectsstudiosettingsfileexists ensuredefaultappsettingsfileexists endindex encodeuricomponent encodethumbnail encodesnapshot encodepath encodedvalue elements effectstabmockup effectsstudiopanelhostbridge effectslist effectseditor effectlistcolumn effectlibrarybuttons effectdefinitionsessionrow effectdefinitionrowview effectchainstab effectchainreorderdropdelegate effectchainlibraryview effectchainlibraryrowmockup effectchainlibraryrow effectchainexpanded editinglayerdisplay durationpart duplicatedlayerwithnewfileid duplicatedfile duplicatedclip duplicated duplicatecurrentlayer droplast dreamy doubletapthreshold dodge documentview documents docssidebarel distantpast distance displaytype displaypath displaying displayindex dispatchtime disabling dirnode different didexit didenter didadvance dialogs dialog detection detect designed deliver deletingpathextension deleteeffect deletecurrentclip deletechain defaultval defaultoffset defaultintdouble defaultframe defaultdouble datestyle dateformat date2 date1 datamosheffect darkmodeswitch darkmodecheckbox darkmode customlabel currentsourcetimebinding currentsourceindexbinding currentsection currentruntimeselectionlabel currentrow currentrelativedocpath currentclipindicatortext countallassets copycurrenttolibrary copied convertstillimagesegmenttovideo convertedurl controlsrow contrast contentsofdirectory contents contentlayoutrect confirmationdialog configureparentwindowforfullscreen configureforlive compositiontab compositionmenu compositionidentity compositing componentsgallerymockup completed comparable compactsourceslist compactsettingslist compactrightsidebarmockup compactleftsidebarmockup compactfavoriteslist colorshift codepanelcontent closebuttons clockwise cliptrimthumbnailstripstore cliptrimrangestrip cliptrimpanelview cliptext clipprovider cliplengthrangerow cliplengthmax clickable cleartooltip clearstatusifcurrent clears clearfilelistcache clearer clearcurrentlayereffect clearcliphistory clearalleffects cleanedchild clampcurrentsourceindex clamp civector cinematic ciimages chosen choosesnapshotsfolder chooseoutputfolder choosefilesourceurl choosefilesource choosecodesourcefileurl choicepicker choiceeditor charactersignoringmodifiers chainspublisher chainnamesavehandler chainheadername chainedeffectsectionreadonly chainedeffectsection cfbundleversion cfbundleshortversionstring cfabsolutetime categories canupdate canrevealinfinder candidatecount cancreatedirectories cancellables canbecomekey camera camelcase cacheintermediates buttonvariationsmockup bundledworkflowurl builds buildrequestplan buildparameterbufferlayout buildlibrary builddocstree bringtofront breadcrumb boundopen boundclose boundbackdrop bound bottomtransportbar boolval board blur blueshifted blocksize bloat blendmodesetter blendmodenamefromcoreimagefilter blendmodeforsourceindex blendmodedisplayname bindingforparameter bindingforlayer bias behind behave beginrequest badge backups backupinvalidsettingsfile backupcorruptfile backup avplayeritemdidplaytoendtime avoiding avassetwriter autoboundset autoboundparameters authorized authoring audiotimepitchalgorithm audiooutputdeviceuniqueid audiodevicechanged audible attrs attempt atomically assetresources assetcount aspectratiooptions aspectfit area appsettingsview applyvolumetoactiveplayer applyeffectsstudiouistate applyaudiodevicetoallplayers applies appinfo appfoldername appendpreviewhistory appendloadedhypnograms appendingpathextension appended apis anywhere animatedphase animated allsatisfy allows allowed alias again affecting advancing advanceorgenerateonclipended advancement advancedsettingsrows addsourcesasnewclip addparameter addmutabletrack addlayerfromfiles adding addfoldersources addeffectbutton addchildwindow activityinsetschanged activejobs activebufferindices activatephotosallifavailable actionatitemend account accessible absolute abouthypnographview 720p


## Notes

- This file is generated from code-level signals and is intentionally heuristic.
- It describes current implementation reality, not intended product direction.
