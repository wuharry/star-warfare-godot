class_name ManufacturerCatalog
extends RefCounted
## Original setting approved by the user. Independent of recovered combat tables.
## Membership uses stable gun IDs; display names and translations are not keys.

const MANUFACTURERS := {
	"lattice": {
		"code": "ILD", "name_en": "Iron-Lattice Defense", "name_zh": "鐵衡聯邦防務",
		"story_zh": "跟隨殖民艦隊擴張的老牌軍方承包商，以統一規格與充足備件建立地位。鐵衡相信一把槍的價值，是前線維修員能否讓它重新服役。面對邊境廠商競爭，公司開始收緊授權，昔日的通用標準也成了維持合約的籌碼。",
		"story_en": "A longstanding military contractor that expanded with the colonial fleets. Common specifications and plentiful spare parts built its reputation: a weapon matters only if a field armorer can return it to service. Facing frontier competition, Iron-Lattice now uses licensing restrictions to defend its contracts.",
		"weapons": ["gun00", "gun03", "gun04", "gun06", "gun07", "gun24", "gun25", "gun39"]
	},
	"rimward": {
		"code": "RFA", "name_en": "Rimward Field Armaments", "name_zh": "邊垣野戰軍械",
		"story_zh": "由邊境維修廠與離開鐵衡的工程師共同成立。航道中斷期間，邊垣靠公開圖紙與地方加工設備維持殖民地守軍的供應。它接受不同工廠留下的製造差異，只要求武器能被當地的人修好；這讓民兵與傭兵成了最忠實的客戶。",
		"story_en": "Founded by frontier repair yards and engineers who left Iron-Lattice. During the shipping blockade, open drawings and local workshops kept colonial defenders supplied. Rimward accepts regional manufacturing differences as long as local crews can repair the equipment. Militia and mercenary units remain its strongest customers.",
		"weapons": ["gun01", "gun02", "gun05", "gun08", "gun09", "gun10", "gun40"]
	},
	"helion": {
		"code": "HPD", "name_en": "Helion Photodynamics", "name_zh": "赫曜光電動力",
		"story_zh": "從艦船供能設備跨入單兵武器的企業巨頭。赫曜將光學、電源與維護服務綁在同一套產品體系中，交付的是整條供應鏈。軍方喜歡它的整合能力，也擔心一旦停付維護合約，整個基地都會受制於同一家公司。",
		"story_en": "A fleet power supplier that expanded into infantry weapons. Helion packages optics, power systems and maintenance into a single product ecosystem. Military buyers value that integration, while commanders worry about making an entire base dependent on one service contract.",
		"weapons": ["gun17", "gun18", "gun19", "gun26", "gun21", "gun38"]
	},
	"vectorline": {
		"code": "VSD", "name_en": "Vectorline Superconductor Dynamics", "name_zh": "矢界超導防務",
		"story_zh": "起家於軌道測量與遠距觀測，後來將精密控制技術投入武器研發。矢界曾拒絕交付未通過驗收的軍方急單，失去大筆訂單，卻贏得專業射手信任。公司至今仍保留逐件驗收紀錄，把可追溯的品質看得比產量重要。",
		"story_en": "Vectorline began in orbital metrology and remote observation before applying precision control to weapons. Refusing to deliver a failed military rush order cost it a major contract but earned specialist shooters' trust. Individual acceptance records remain more important to the company than production volume.",
		"weapons": ["gun22", "gun29", "gun44", "gun34", "gun35", "gun43"]
	},
	"crucible": {
		"code": "CHO", "name_en": "Crucible Heavy Ordnance", "name_zh": "坩堝重裝兵械",
		"story_zh": "由船塢重型設備與破拆機具轉型而來，擅長把大型工程技術縮進士兵能攜帶的裝備。坩堝要求操作件能讓戴厚手套的人辨認，維修艙門也必須容易接近。前線常抱怨它的設備笨重，卻很少抱怨找不到該拆的地方。",
		"story_en": "A former shipyard equipment and demolition manufacturer, Crucible specializes in making heavy engineering portable. Its controls must remain recognizable through thick gloves and its service compartments accessible. Troops complain about the bulk, but rarely about finding the part that needs repair.",
		"weapons": ["gun11", "gun12", "gun13", "gun14", "gun15", "gun16", "gun20", "gun31"]
	},
	"parallax": {
		"code": "PAL", "name_en": "Parallax Advanced Labs", "name_zh": "裂相前沿實驗室",
		"story_zh": "對外承接研究委託，資金來源卻藏在多層企業背後。裂相收購戰場回收的未知裝置，讓私人部隊參與試製武器測試。它的產品通常以專案代號流通；有些留下完整紀錄，有些只有一張刪去研發人員姓名的出廠單。",
		"story_en": "An experimental contractor financed through layers of shell companies. Parallax buys unidentified battlefield hardware and places prototypes with private units. Its weapons circulate under project names: some have complete records, while others arrive with the researchers' names erased from the shipping papers.",
		"weapons": ["gun30", "gun32", "gun36", "gun37", "gun41", "gun42", "gun45", "gun46"]
	},
	"thornring": {
		"code": "THS", "name_en": "Thornring Hazard Systems", "name_zh": "棘環搜救工造",
		"story_zh": "由救援人員與外骨骼技師成立，最初供應殘骸切割與搬運設備。一次撤離行動中，工具成了救援隊最後的防身手段，促成軍用產品線。棘環仍沿用搜救裝備的設計思考：握得住、辨認得出操作位置，而且能帶著使用者回來。",
		"story_en": "Established by rescuers and exoskeleton technicians to build wreckage-cutting and handling equipment. When those tools became a rescue team's last defense during an evacuation, a military line followed. Thornring still designs around a rescuer's needs: a secure grip, clear controls and a way home.",
		"weapons": ["gun27", "gun28", "gun33", "gun23"]
	}
}

## Each entry is [Traditional Chinese, English]. Narrative, not stat modifiers.
const WEAPON_STORIES := {
	"gun00": ["鐵衡 FR 系列的入門勤務步槍，常見於新兵配發與基地警備。它代表公司的基本承諾：先讓部隊長期用得起，再談更高的火力。", "The entry service rifle of Iron-Lattice's FR line, issued to recruits and base guards. It embodies the company's first promise: sustainable fleet-wide service before additional firepower."],
	"gun01": ["邊垣為地方守軍設計的常備步槍。MA72 的採購理念是讓分散的殖民地也能建立自己的武器供應，而不必等待中央艦隊運補。", "Rimward's regular rifle for local defense forces. The MA72 program was intended to give scattered colonies a supply of their own rather than depend on central fleet deliveries."],
	"gun02": ["MS06 是邊垣步槍產品線中偏重持續射擊的選擇。它的訂單多來自需要擴充火力、又不想更換整套維修體系的前線部隊。", "The MS06 emphasizes sustained fire within Rimward's rifle line. Its customers want additional firepower without abandoning their existing maintenance network."],
	"gun03": ["FR43C 延續 FR 系列的勤務定位，面向需求更高的戰鬥單位。鐵衡將它作為從基礎配發走向主力裝備的升階選擇。", "The FR43C carries the FR service line into more demanding combat assignments. Iron-Lattice markets it as the next step beyond basic issue."],
	"gun04": ["FL334AR 面向重視單發威力的步槍採購案。它反映鐵衡的另一種取捨：願意增加供能負擔，換取更強的步兵火力。", "The FL334AR targets rifle contracts that prioritize power per shot. It accepts a greater energy burden in exchange for heavier infantry firepower."],
	"gun05": ["TB10-LW 是邊垣高階步槍方案，為前線提供更積極的火力選擇。它不以節省補給聞名，採購者必須連同供能需求一起考慮。", "Rimward's TB10-LW offers an aggressive upper-tier rifle option. Economy is not its selling point; buyers must plan for its energy demands."],
	"gun06": ["TSG-03 是鐵衡的基礎近距勤務武器，偏向成本可控的散彈配發。它常與入門步槍一起出現在基地的標準裝備清單上。", "The TSG-03 is Iron-Lattice's economical close-range service shotgun, commonly listed beside entry rifles in base equipment orders."],
	"gun07": ["SD58 延續鐵衡散彈產品線，以較慢的射擊間隔換取更強的單次打擊。公司將它定位為近距防線的補強裝備。", "The SD58 trades a slower firing cadence for a heavier individual hit within Iron-Lattice's shotgun line. It is sold as reinforcement for close defensive positions."],
	"gun08": ["WD03S 是邊垣面向地方採購的均衡散彈方案。它的產品故事沒有華麗的試驗代號，只有守軍能否負擔下一批裝備的現實考量。", "The WD03S is Rimward's balanced shotgun for local procurement. Its story is about whether a garrison can afford its next shipment, rather than an elaborate experimental designation."],
	"gun09": ["S92M 是邊垣較重視打擊威力的散彈方案。射手需要接受較慢的射擊規律與更高的供能成本，換取每次開火的分量。", "Rimward's S92M favors a heavier shotgun strike, asking its operator to accept a slower cadence and a greater energy cost."],
	"gun10": ["T740 位於邊垣散彈產品線的高階位置。它是地方部隊不再滿足於基本自衛、開始採購專用重火力時會考慮的型號。", "The T740 occupies the upper end of Rimward's shotgun line, aimed at local units moving beyond basic self-defense toward dedicated heavy firepower."],
	"gun11": ["RPG-21 是坩堝便攜式範圍打擊產品線的起點。相較複雜的試驗武器，它的採購目的非常直接：讓步兵攜帶能清理聚集目標的火力。", "The RPG-21 introduces Crucible's portable area-fire line. Its procurement purpose is direct: give infantry a weapon for clustered targets."],
	"gun12": ["RPG-24 將坩堝的火箭筒方案推向更重的打擊需求。威力之外，較高的每發供能負擔也是前線部署時必須接受的代價。", "The RPG-24 extends Crucible's launcher line toward heavier strikes, accompanied by a larger energy commitment for each shot."],
	"gun13": ["RPG-31 是坩堝火箭筒系列中的高階方案。它針對需要集中範圍火力的採購案，將補給成本排在打擊能力之後。", "The RPG-31 is Crucible's upper-tier launcher for concentrated area fire, prioritizing striking power over supply economy."],
	"gun14": ["Vox-07 是坩堝榴彈發射器的入門型號。它讓原本只配發直射武器的小隊，也能取得自己的範圍打擊選擇。", "The Vox-07 is the entry to Crucible's grenade-launcher line, bringing an area-fire option to squads previously equipped only for direct fire."],
	"gun15": ["M347 是坩堝榴彈產品線的中段方案，在射擊規律與單發威力之間取捨。它的定位是可持續部署的班組支援裝備。", "The M347 balances firing cadence and individual power in Crucible's grenade line. It is positioned as a regular squad-support weapon."],
	"gun16": ["Ge09x 是坩堝面向更高打擊需求的榴彈方案。型錄強調火力與波及範圍，也要求使用部隊為較高的能源消耗預留補給。", "The Ge09x addresses heavier grenade-fire requirements, emphasizing power and area coverage while demanding more generous energy provisioning."],
	"gun17": ["LG002B 是赫曜將雷射技術帶入常規單兵採購的代表型號。它標誌著公司從供應電力設備，走向直接提供前線火力的轉折。", "The LG002B represents Helion's move into regular infantry laser procurement, turning a power-equipment supplier into a direct provider of frontline firepower."],
	"gun18": ["M2456s 延伸赫曜的雷射產品線，服務需要更強輸出的軍方客戶。公司將它納入既有供能與維護合約，而非單獨出售的孤立裝備。", "The M2456s extends Helion's laser line for customers seeking greater output. It is marketed as part of the company's power and maintenance ecosystem."],
	"gun19": ["NOVA27 是赫曜高階雷射方案的門面。它在產品展示中象徵公司的技術地位，也讓軍方更深地依賴赫曜的整套支援體系。", "The NOVA27 is a showcase for Helion's upper-tier laser program, promoting its technical standing and drawing buyers deeper into its support ecosystem."],
	"gun20": ["Plasma Neo 是坩堝吸收異星電漿技術後推出的產品。這條研發線把未知裝置轉為可交付的武器，也讓傳統重裝兵械廠跨入新的技術領域。", "Plasma Neo emerged from Crucible's adaptation of alien plasma technology, turning recovered devices into a deliverable weapon and opening a new field for the heavy-ordnance firm."],
	"gun21": ["Laser Cannon 是赫曜重型光束產品線的展示級裝備。它不再只是步槍的替代品，而是公司爭取重火力採購合約的重要名片。", "Laser Cannon showcases Helion's heavy beam line. It is more than a rifle alternative: it is the company's bid for heavy-firepower contracts."],
	"gun22": ["Light Bow 是矢界能量弓產品線的起點。公司保留弓形產品的獨立身分，將精密控制理念帶入與磁軌步槍不同的發射形式。", "Light Bow begins Vectorline's energy-bow line, carrying its precision-control philosophy into a launch format distinct from its rail rifles."],
	"gun23": ["Energy Glove 是棘環將手部外骨骼經驗帶入武器設計的成果。它延續搜救裝備貼近操作者身體的思路，而非照搬長槍的持握形式。", "Energy Glove applies Thornring's experience with hand-mounted exoskeleton equipment to weapons, keeping the device close to its operator rather than imitating a long gun."],
	"gun24": ["MCP76 是鐵衡班組支援產品線的常規選擇。它把公司的採購目標從單兵配發延伸到持續火力，但也提高了小隊的供能需求。", "The MCP76 is Iron-Lattice's regular squad-support offering, extending its service-equipment role into sustained fire and greater squad energy demands."],
	"gun25": ["M-27B1 是鐵衡機槍系列的進階型號。公司將它提供給需要更密集火力的部隊，並與整套支援武器維護計畫一起交付。", "The M-27B1 advances Iron-Lattice's machine-gun line for units seeking denser fire, supplied alongside its support-weapon maintenance program."],
	"gun26": ["LIT07 是赫曜吸收異星技術的雷射研發成果。對外型錄強調全新設計，內部則把它視為下一代供能產品能否走上戰場的試金石。", "The LIT07 brings alien-derived research into Helion's laser line. Publicly a new design, internally it tests whether the next generation of power products is ready for field service."],
	"gun27": ["Cutter 保留棘環切割工具的命名傳統，是近戰產品線的基礎型號。它代表公司軍用化的起點：讓原本用來打開逃生通道的工具，也能保護使用者。", "Cutter retains Thornring's cutting-tool naming tradition as its basic melee model: a tool for opening escape routes reworked to protect the person holding it."],
	"gun28": ["Passer 是棘環在 Cutter 之後推出的進階近戰方案。公司將前線回報納入後續設計，讓軍用產品線逐漸脫離臨時改裝的身分。", "Passer follows Cutter as Thornring's advanced melee offering. Field reports helped turn a line of improvised conversions into purpose-built military equipment."],
	"gun29": ["Trinity 延伸矢界的能量弓研究，嘗試讓同一次射擊承擔更大的火力需求。它保留獨立的產品名稱，與常規磁軌系列分開管理。", "Trinity extends Vectorline's energy-bow research toward greater firepower per release, retaining a distinct product identity from its regular rail line."],
	"gun30": ["BLACK STARS 是裂相以專案代號交付的火箭武器。它與傳統廠商逐代更新的型號不同，留下的公開資料主要來自外部測試部隊。", "BLACK STARS is a Parallax rocket project delivered under its research codename. Unlike a conventional model lineage, its public record largely comes from external test units."],
	"gun31": ["Crab 是坩堝電漿產品線的後續試製方案。它延續 Plasma Neo 開啟的技術路線，把公司擅長的重型工程思考帶入電漿武器研發。", "Crab is a later prototype in Crucible's plasma line, continuing the research opened by Plasma Neo with the firm's heavy-engineering approach."],
	"gun32": ["Morpheus 是裂相研究多束能量投射的專案。它借用了散彈武器的交戰思路，卻沒有歸入傳統實彈散彈槍的採購系列。", "Morpheus is Parallax's multi-beam projection project, borrowing the engagement concept of a shotgun without belonging to a conventional ballistic shotgun line."],
	"gun33": ["WINDBLADE 讓棘環近戰產品線走出單純接觸式工具的框架。它是公司持續將搜救工程經驗轉為專用武器的一個明顯轉折。", "WINDBLADE takes Thornring's melee line beyond the concept of a contact tool, marking another step from rescue engineering toward dedicated weapons."],
	"gun34": ["R100-RAILGUN 是矢界遠距精密武器的代表。它以清楚的產品編號進入軍方採購體系，背後仍維持公司逐件驗收的傳統。", "The R100-RAILGUN represents Vectorline's long-range precision line, combining a regular military model designation with its tradition of individual acceptance testing."],
	"gun35": ["R700-AA 是矢界磁軌產品線的高階方案。它服務的客戶對遠距打擊有更高要求，也願意承擔專門裝備的採購與維護成本。", "The R700-AA occupies the upper end of Vectorline's rail line for customers willing to support a more specialized long-range weapon."],
	"gun36": ["WHITE DRILL 是裂相以釘狀投射物為研究方向的專案。它保留試驗名稱進入市場，使外界難以從型號判斷它與其他武器的研發關係。", "WHITE DRILL explores nail-like projectiles within Parallax's research portfolio. Retaining its experimental name obscures its development relationship to other weapons."],
	"gun37": ["BLACK DISK 是裂相盤狀投射裝置的專案名稱。回收樣本、試製件與正式交付品之間的界線並不公開，使用紀錄因而比型錄更有價值。", "BLACK DISK names Parallax's disc-projector project. With recovered samples, prototypes and delivered units poorly distinguished in public records, field reports matter more than catalogs."],
	"gun38": ["XMAX-TREE 最初是赫曜的節慶展示專案，戰時才轉入裝備清單。公司保留了它不尋常的名稱，使這把武器成為產品線中特別醒目的例外。", "XMAX-TREE began as a Helion seasonal demonstration before entering wartime equipment lists. Its unusual name remains a conspicuous exception in the product line."],
	"gun39": ["M-Z7B2 是鐵衡重視持續火力的高階機槍方案。它面向具備完整補給與維修能力的部隊，反映公司以整套支援體系交付裝備的習慣。", "The M-Z7B2 is an upper-tier Iron-Lattice machine gun intended for units with substantial supply and maintenance support, reflecting the company's system-wide procurement approach."],
	"gun40": ["AST-KK 是邊垣步槍研發中的高階成果。它讓這家以地方維修網絡起家的廠商，能直接爭取原本由大型軍工企業主導的火力採購案。", "The AST-KK is an upper-tier result of Rimward's rifle research, allowing a company rooted in local repair networks to compete for major military firepower contracts."],
	"gun41": ["J.O.K.E 是裂相特殊榴彈專案的代號。研發團隊沒有在公開文件中解釋縮寫，外部測試人員只能靠交付批次與使用紀錄辨別版本。", "J.O.K.E is a Parallax special-grenade codename whose initials remain unexplained in public documents. External testers identify versions through delivery batches and field records."],
	"gun42": ["Spring 是裂相的手持能量投射專案，與棘環的搜救外骨骼產品有不同出身。它沿用簡短代號，沒有公開完整的技術沿革。", "Spring is a Parallax handheld energy-projection project, with a different origin from Thornring's rescue exoskeleton equipment. Its brief codename reveals little of its technical lineage."],
	"gun43": ["Reflection 是矢界保留專案名稱的精密武器試製案。它讓公司在制式 R 系列之外探索新方向，但仍必須接受相同的交付驗收要求。", "Reflection retains its project name as a Vectorline precision-weapon prototype, exploring a path beyond the regular R series while remaining subject to the same acceptance requirements."],
	"gun44": ["TheArrow 是矢界能量弓研發中的另一條路線。它沒有直接沿用 Light Bow 的型號序列，而是以獨立名稱標示不同的投射研究方向。", "TheArrow follows a separate branch of Vectorline's energy-bow research, using an independent name rather than presenting itself as a simple Light Bow model revision."],
	"gun45": ["U.F.O 是裂相特殊投射裝置的專案名稱。它刻意保留容易被記住的外部代號，真正的研發編號則只出現在未公開的交付文件中。", "U.F.O is the public codename for a Parallax special projector. The memorable label conceals a development designation confined to non-public delivery documents."],
	"gun46": ["Spreader 延續裂相多束能量投射的研究方向。它與 Morpheus 在產品定位上相近，但以獨立專案管理，沒有被包裝成單純的外觀改款。", "Spreader continues Parallax's multi-beam projection research. Close to Morpheus in purpose, it is managed as a separate project rather than a cosmetic model revision."]
}

static var _weapon_index: Dictionary = _build_weapon_index()

static func _build_weapon_index() -> Dictionary:
	var result := {}
	for id: String in MANUFACTURERS:
		for weapon: String in MANUFACTURERS[id].weapons:
			result[weapon] = id
	return result

static func get_manufacturer_for_weapon(weapon_id: String) -> Dictionary:
	return MANUFACTURERS.get(_weapon_index.get(weapon_id, ""), {}).duplicate(true)

static func localized(data: Dictionary, field: String) -> String:
	return str(data.get(field + ("_zh" if TranslationServer.get_locale().begins_with("zh") else "_en"), ""))

static func weapon_description(weapon_id: String) -> String:
	var text: Array = WEAPON_STORIES.get(weapon_id, ["", ""])
	return str(text[0 if TranslationServer.get_locale().begins_with("zh") else 1])
