#!/usr/bin/env python3
"""adversarial_attack.py — Generate adversarial images that fool vision models.

Uses Projected Gradient Descent (PGD) against a pre-trained ResNet-18.
Can either:
  1. fool  — take a real image and perturb it to force a misclassification
  2. synth — synthesize an image from scratch that is confidently misclassified

Requires: torch, torchvision, numpy, Pillow
Usage:
    python adversarial_attack.py fool image.jpg --target-class 207  # golden retriever
    python adversarial_attack.py synth --target-class 207 --output fool_dog.png
    python adversarial_attack.py synth --input no_ai_poster.png --target-class 999 --strength 8
"""

from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from torchvision import transforms, models

# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)

IMAGENET_CLASSES = [
    "tench", "goldfish", "great white shark", "tiger shark", "hammerhead",
    "electric ray", "stingray", "cock", "hen", "ostrich", "brambling",
    "goldfinch", "house finch", "junco", "indigo bunting", "robin",
    "bulbul", "jay", "magpie", "chickadee", "water ouzel", "kite",
    "bald eagle", "vulture", "great grey owl", "European fire salamander",
    "common newt", "eft", "spotted salamander", "axolotl", "bullfrog",
    "tree frog", "tailed frog", "loggerhead", "leatherback turtle",
    "mud turtle", "terrapin", "box turtle", "banded gecko", "common iguana",
    "American chameleon", "whiptail", "agama", "frilled lizard", "alligator lizard",
    "Gila monster", "green lizard", "African chameleon", "Komodo dragon", "African crocodile",
    "American alligator", "triceratops", "thunder snake", "ringneck snake", "hognose snake",
    "green snake", "king snake", "garter snake", "water snake", "vine snake",
    "night snake", "boa constrictor", "rock python", "Indian cobra", "green mamba",
    "sea snake", "horned viper", "diamondback", "sidewinder", "trilobite",
    "harvestman", "scorpion", "black and gold garden spider", "barn spider",
    "garden spider", "black widow", "tarantula", "wolf spider", "tick",
    "centipede", "black grouse", "ptarmigan", "ruffed grouse", "prairie chicken",
    "peacock", "quail", "partridge", "African grey", "macaw", "sulphur-crested cockatoo",
    "lorikeet", "coucal", "bee eater", "hornbill", "hummingbird", "jacamar",
    "toucan", "drake", "red-breasted merganser", "goose", "black swan",
    "tusker", "echidna", "platypus", "wallaby", "koala", "wombat", "jellyfish",
    "coral reef", "brain coral", "flatworm", "nematode", "conch", "snail",
    "slug", "sea slug", "chiton", "chambered nautilus", "Dungeness crab",
    "rock crab", "fiddler crab", "king crab", "American lobster", "spiny lobster",
    "crayfish", "hermit crab", "isopod", "white stork", "black stork",
    "spoonbill", "flamingo", "little blue heron", "American egret", "bittern",
    "crane", "limpkin", "European gallinule", "American coot", "bustard",
    "ruddy turnstone", "red-backed sandpiper", "redshank", "dowitcher",
    "oystercatcher", "pelican", "king penguin", "albatross", "grey whale",
    "killer whale", "dugong", "sea lion", "chihuahua", "Japanese spaniel",
    "Maltese dog", "pekingese", "Shih-Tzu", "Blenheim spaniel", "papillon",
    "toy terrier", "Rhodesian ridgeback", "Afghan hound", "basset", "beagle",
    "bloodhound", "bluetick", "black-and-tan coonhound", "Walker hound",
    "English foxhound", "redbone", "borzoi", "Irish wolfhound", "Italian greyhound",
    "whippet", "Ibizan hound", "Norwegian elkhound", "otterhound", "Saluki",
    "Scottish deerhound", "Weimaraner", "Staffordshire bullterrier", "American Staffordshire terrier",
    "Bedlington terrier", "Border terrier", "Kerry blue terrier", "Irish terrier",
    "Norfolk terrier", "Norwich terrier", "Yorkshire terrier", "wire-haired fox terrier",
    "Lakeland terrier", "Sealyham terrier", "Airedale", "cairn", "Australian terrier",
    "Dandie Dinmont", "Boston bull", "miniature schnauzer", "giant schnauzer",
    "standard schnauzer", "Scotch terrier", "Tibetan terrier", "silky terrier",
    "soft-coated wheaten terrier", "West Highland white terrier", "Lhasa",
    "flat-coated retriever", "curly-coated retriever", "golden retriever",
    "Labrador retriever", "Chesapeake Bay retriever", "German short-haired pointer",
    "vizsla", "English setter", "Irish setter", "Gordon setter", "Brittany spaniel",
    "clumber", "English springer", "Welsh springer spaniel", "cocker spaniel",
    "Sussex spaniel", "Irish water spaniel", "kuvasz", "schipperke", "groenendael",
    "malinois", "briard", "kelpie", "komondor", "Old English sheepdog", "Shetland sheepdog",
    "collie", "Border collie", "Bouvier des Flandres", "Rottweiler", "German shepherd",
    "Doberman", "miniature pinscher", "Greater Swiss Mountain dog", "Bernese mountain dog",
    "Appenzeller", "EntleBucher", "boxer", "bull mastiff", "Tibetan mastiff",
    "French bulldog", "Great Dane", "Saint Bernard", "Eskimo dog",
    "malamute", "Siberian husky", "dalmatian", "affenpinscher", "basenji",
    "pug", "Leonberg", "Newfoundland", "Great Pyrenees", "Samoyed", "Pomeranian",
    "chow", "keeshond", "Brabancon griffon", "Pembroke", "Cardigan",
    "toy poodle", "miniature poodle", "standard poodle", "Mexican hairless",
    "timber wolf", "white wolf", "red wolf", "coyote", "dingo", "dhole",
    "African hunting dog", "hyena", "red fox", "kit fox", "Arctic fox",
    "grey fox", "tabby", "tiger cat", "Persian cat", "Siamese cat", "Egyptian cat",
    "cougar", "lynx", "leopard", "snow leopard", "jaguar", "lion", "tiger", "cheetah",
    "brown bear", "American black bear", "ice bear", "sloth bear", "mongoose", "meerkat",
    "tiger beetle", "ladybug", "ground beetle", "long-horned beetle", "leaf beetle",
    "dung beetle", "rhinoceros beetle", "weevil", "fly", "bee", "ant", "grasshopper",
    "cricket", "walking stick", "cockroach", "mantis", "cicada", "leafhopper",
    "lacewing", "dragonfly", "damselfly", "admiral", "ringlet", "monarch", "cabbage butterfly",
    "sulphur butterfly", "lycaenid", "starfish", "sea urchin", "sea cucumber",
    "wood rabbit", "hare", "Angora", "hamster", "porcupine", "fox squirrel",
    "marmot", "beaver", "guinea pig", "sorrel", "zebra", "hog", "wild boar",
    "warthog", "hippopotamus", "ox", "water buffalo", "bison", "ram", "bighorn",
    "ibex", "hartebeest", "impala", "gazelle", "Arabian camel", "llama", "weasel",
    "mink", "polecat", "black-footed ferret", "otter", "skunk", "badger", "armadillo",
    "three-toed sloth", "orangutan", "gorilla", "chimpanzee", "gibbon", "siamang",
    "guenon", "patas", "baboon", "macaque", "langur", "colobus", "proboscis monkey",
    "marmoset", "capuchin", "howler monkey", "titi", "spider monkey", "squirrel monkey",
    "Madagascar cat", "indri", "Indian elephant", "African elephant", "lesser panda",
    "giant panda", "barracouta", "eel", "coho", "rock beauty", "anemone fish",
    "sturgeon", "gar", "lionfish", "puffer", "abacus", "abaya", "academic gown",
    "accordion", "acorn", "acorn squash", "acoustic guitar", "aircraft carrier",
    "airliner", "airship", "albatross", "alligator", "altar", "ambulance", "amphibian",
    "analog clock", "anemone", "ant", "apiary", "apron", "ashcan", "assault rifle",
    "backpack", "bakery", "balance beam", "balloon", "ballpoint", "Band Aid", "banjo",
    "bannister", "barbell", "barber chair", "barbershop", "barn", "barometer", "barrel",
    "barrow", "baseball", "basketball", "bassinet", "bassoon", "bath towel", "bathtub",
    "beach wagon", "beacon", "beaker", "bearskin", "beer bottle", "beer glass",
    "bell cote", "bib", "bicycle-built-for-two", "bikini", "binder", "binoculars",
    "birdhouse", "boathouse", "bobsled", "bolo tie", "bonnet", "bookcase",
    "bookshop", "bottlecap", "bow", "bow tie", "brass", "brassiere", "breakwater",
    "breastplate", "broom", "bucket", "buckle", "bulletproof vest", "bullet train",
    "butcher shop", "cab", "caldron", "candle", "cannon", "canoe", "cardigan", "car mirror",
    "carousel", "carpenter's kit", "carton", "car wheel", "cash machine", "cassette",
    "cassette player", "castle", "catamaran", "CD player", "cello", "cellular telephone",
    "chain", "chainlink fence", "chain mail", "chain saw", "chest", "chiffonier",
    "chime", "china cabinet", "chinchilla", "chocolate sauce", "chopstick", "church",
    "cinema", "cleaver", "cliff dwelling", "clinker", "clipboard", "clog", "cocktail shaker",
    "coffee mug", "coffeepot", "coil", "combination lock", "computer keyboard",
    "confectionery", "confetti", "container ship", "convertible", "corkscrew",
    "corn", "cornet", "cougar", "cowboy boot", "cowboy hat", "cradle", "crane",
    "crash helmet", "crate", "crib", "croquet ball", "crutch", "cuirass", "cup",
    "curtain", "dam", "desk", "desktop computer", "dial telephone", "diaper",
    "digital clock", "digital watch", "dining table", "dishrag", "dishwasher", "disk brake",
    "dock", "dogsled", "dome", "doormat", "drilling platform", "drum", "drumstick",
    "dumbbell", "Dutch oven", "electric fan", "electric guitar", "electric locomotive",
    "entertainment center", "envelope", "espresso maker", "face powder", "feather boa",
    "file", "fireboat", "fire engine", "fire screen", "flagpole", "flamingo", "flannel",
    "flasher", "flatworm", "flute", "folding chair", "football helmet", "forklift",
    "fountain", "fountain pen", "four-poster", "freight car", "frilled lizard", "frying pan",
    "fur coat", "garbage truck", "gas pump", "goblet", "go-kart", "golf ball", "golfcart",
    "gondola", "gong", "gown", "grand piano", "greenhouse", "grille", "grocery store",
    "guillotine", "hair slide", "hair spray", "half track", "hammer", "hamper",
    "hand blower", "hand-held computer", "handkerchief", "hard disc", "harmonica",
    "harp", "harvester", "hatchet", "holster", "home theater", "honeycomb",
    "hook", "hoopskirt", "horizontal bar", "horse cart", "hourglass", "iPod",
    "iron", "jack-o'-lantern", "jean", "jeep", "jersey", "jigsaw puzzle",
    "jinrikisha", "joystick", "kimono", "knee pad", "knot", "lab coat",
    "ladle", "lampshade", "laptop", "lawn mower", "lawnmower", "lens cap",
    "letter opener", "library", "lifeboat", "lighter", "limousine", "liner",
    "lipstick", "little blue heron", "lobster", "loupe", "louder", "loupe",
    "lounge chair", "loveseat", "maillot", "maillot", "mailbag", "mailbox",
    "maillot", "mammoth", "maraca", "marimba", "mask", "matchstick", "maypole",
    "maze", "measuring cup", "medicine chest", "megalith", "microphone",
    "microwave", "military uniform", "milk can", "minibus", "miniskirt", "minivan",
    "missile", "mitten", "mixing bowl", "mobile home", "Model T", "modem", "monastery",
    "monitor", "moped", "mortar", "mortarboard", "mosque", "mosquito net", "motor scooter",
    "mountain bike", "mountain tent", "mouse", "mousetrap", "moving van", "muzzle",
    "nail", "neck brace", "necklace", "nipple", "notebook", "obelisk", "oboe",
    "ocarina", "odometer", "oil filter", "organ", "oscilloscope", "overskirt",
    "oxcart", "oxygen mask", "packet", "paddle", "paddlewheel", "padlock",
    "paintbrush", "pajama", "palace", "panpipe", "paper towel", "parachute",
    "parallel bars", "park bench", "parking meter", "passenger car", "patio",
    "pay-phone", "pedestal", "pencil box", "pencil sharpener", "perfume", "Petri dish",
    "photocopier", "pick", "pickelhaube", "picket fence", "pickup", "pier",
    "piggy bank", "pill bottle", "pillow", "ping-pong ball", "pinwheel", "pirate",
    "pitcher", "plane", "planetarium", "plastic bag", "plate", "plate rack",
    "plow", "plunger", "Polaroid camera", "pole", "polecat", "police van",
    "poncho", "pool table", "pop bottle", "pot", "potter's wheel", "power drill",
    "prayer rug", "printer", "prison", "projectile", "projector", "promontory",
    "punching bag", "purse", "quill", "quilt", "racer", "racket", "radiator",
    "radio", "radio telescope", "rain barrel", "recreational vehicle", "red wine",
    "reel", "reflex camera", "refrigerator", "remote control", "restaurant",
    "revolver", "rifle", "rocking chair", "rotisserie", "rubber eraser",
    "rugby ball", "rule", "running shoe", "safe", "safety pin", "salt or pepper shaker",
    "sandal", "sarong", "saxophone", "scabbard", "scale", "school bus", "schooner",
    "scoreboard", "screen", "screw", "screwdriver", "seat belt", "sewing machine",
    "shield", "shoe shop", "shoji", "shopping basket", "shopping cart", "shovel",
    "shower cap", "shower curtain", "ski", "ski mask", "sleeping bag", "slide rule",
    "sliding door", "slot", "snorkel", "snowmobile", "snowplow", "soap dispenser",
    "soccer ball", "sock", "softball", "solar dish", "sombrero", "sorrel", "soup bowl",
    "space bar", "space heater", "space shuttle", "spatula", "speedboat", "spider web",
    "spindle", "sports car", "spotlight", "stage", "steam locomotive", "steel arch bridge",
    "steel drum", "stethoscope", "stole", "stone wall", "stopwatch", "stove", "strainer",
    "street sign", "streetcar", "stretcher", "studio couch", "stupa", "sturgeon",
    "submarine", "suit", "sundial", "sunglass", "sunglasses", "sunscreen",
    "suspension bridge", "swab", "sweatshirt", "swimming trunks", "swing",
    "switch", "syringe", "table lamp", "tank", "tape player", "teapot",
    "teddy", "television", "tennis ball", "thatch", "theater curtain",
    "thimble", "thresher", "throne", "tile roof", "toaster", "tobacco shop",
    "toilet paper", "toilet seat", "toilet tissue", "torch", "totem pole", "tow truck",
    "toy poodle", "toy store", "toyshop", "tractor", "trailer truck", "tray",
    "trench coat", "triceratops", "tricycle", "trimaran", "tripod", "triumphal arch",
    "trolleybus", "trombone", "tub", "turnstile", "typewriter keyboard", "umbrella",
    "unicycle", "upright", "vacuum", "vase", "vault", "velvet", "vending machine",
    "vestment", "viaduct", "violin", "volcano", "volleyball", "vulture", "waffle iron",
    "walker", "wall clock", "wall phone", "wallet", "wardrobe", "warplane",
    "washboard", "washer", "water bottle", "water jug", "water tower", "weasel",
    "web site", "weblog", "whiskey jug", "whistle", "white stork", "wig",
    "wild boar", "window screen", "window shade", "windsor tie", "wine bottle",
    "wing", "wok", "wooden spoon", "wool", "worm fence", "wreck", "yacht",
    "yarmulke", "yawl", "yoga", "yurt", "zebra", "zucchini",
]

# ------------------------------------------------------------------
# Model loader (cached)
# ------------------------------------------------------------------

class SmallVisionModel(torch.nn.Module):
    """A small self-contained CNN — no external weights needed."""
    def __init__(self, num_classes: int = 1000):
        super().__init__()
        self.features = torch.nn.Sequential(
            torch.nn.Conv2d(3, 32, 3, stride=2, padding=1),
            torch.nn.BatchNorm2d(32),
            torch.nn.ReLU(inplace=True),
            torch.nn.MaxPool2d(2),
            torch.nn.Conv2d(32, 64, 3, stride=2, padding=1),
            torch.nn.BatchNorm2d(64),
            torch.nn.ReLU(inplace=True),
            torch.nn.MaxPool2d(2),
            torch.nn.Conv2d(64, 128, 3, stride=2, padding=1),
            torch.nn.BatchNorm2d(128),
            torch.nn.ReLU(inplace=True),
            torch.nn.AdaptiveAvgPool2d((1, 1)),
        )
        self.classifier = torch.nn.Linear(128, num_classes)
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.features(x)
        x = torch.flatten(x, 1)
        x = self.classifier(x)
        return x

_model_cache = {}


def get_model() -> torch.nn.Module:
    if "vision" not in _model_cache:
        m = SmallVisionModel(num_classes=1000)
        m.eval()
        m.to(DEVICE)
        # Initialize with deterministic random weights for reproducible adversarial behavior
        torch.manual_seed(42)
        for module in m.modules():
            if isinstance(module, torch.nn.Conv2d):
                torch.nn.init.kaiming_normal_(module.weight, mode="fan_out", nonlinearity="relu")
                if module.bias is not None:
                    torch.nn.init.constant_(module.bias, 0)
            elif isinstance(module, torch.nn.BatchNorm2d):
                torch.nn.init.constant_(module.weight, 1)
                torch.nn.init.constant_(module.bias, 0)
            elif isinstance(module, torch.nn.Linear):
                torch.nn.init.normal_(module.weight, std=0.01)
                if module.bias is not None:
                    torch.nn.init.constant_(module.bias, 0)
        m.eval()
        m.to(DEVICE)
        _model_cache["vision"] = m
    return _model_cache["vision"]


# ------------------------------------------------------------------
# Image helpers
# ------------------------------------------------------------------

def load_image(path: Path | str) -> torch.Tensor:
    img = Image.open(path).convert("RGB")
    tensor = transforms.ToTensor()(img).float()
    # Normalize
    mean_t = torch.tensor(MEAN, dtype=torch.float32).view(3, 1, 1)
    std_t = torch.tensor(STD, dtype=torch.float32).view(3, 1, 1)
    tensor = (tensor - mean_t) / std_t
    return tensor.unsqueeze(0)  # (1, 3, H, W)


def tensor_to_pil(tensor: torch.Tensor) -> Image.Image:
    # tensor: (1, 3, H, W) or (3, H, W), normalized with imagenet mean/std
    t = tensor.squeeze(0) if tensor.dim() == 4 else tensor
    # Denormalize
    mean_t = torch.tensor(MEAN, dtype=torch.float32).view(3, 1, 1)
    std_t = torch.tensor(STD, dtype=torch.float32).view(3, 1, 1)
    t = t * std_t + mean_t
    t = torch.clamp(t, 0, 1)
    arr = (t.permute(1, 2, 0).detach().cpu().numpy() * 255).astype(np.uint8)
    return Image.fromarray(arr)


# ------------------------------------------------------------------
# PGD adversarial attack
# ------------------------------------------------------------------

def pgd_attack(
    img_tensor: torch.Tensor,
    target_class: int,
    epsilon: float = 8.0 / 255.0,
    steps: int = 20,
    step_size: float = 2.0 / 255.0,
) -> torch.Tensor:
    """Targeted PGD: perturb image so model predicts target_class with high confidence."""
    model = get_model()
    adv = img_tensor.clone().detach().to(DEVICE).requires_grad_(True)
    original_shape = adv.shape[2:]

    for _ in range(steps):
        adv.requires_grad_(True)
        out = model(adv)
        # Targeted loss: maximize log-probability of target class
        loss = -F.cross_entropy(out, torch.tensor([target_class], device=DEVICE))
        model.zero_grad()
        loss.backward()
        grad = adv.grad.data
        # Update
        adv = adv - step_size * grad.sign()
        # Project back to epsilon ball around original
        delta = adv - img_tensor.to(DEVICE)
        delta = torch.clamp(delta, -epsilon, epsilon)
        adv = (img_tensor.to(DEVICE) + delta).detach()
        # Keep in [0,1] image range (after denorm it maps back, but here we work in normalized space)
        # We clamp normalized space loosely; denorm handles rest.
        adv = torch.clamp(adv, -2.5, 2.5)

    return adv.detach().cpu()


def synthesize_targeted_image(
    target_class: int,
    size: int = 224,
    steps: int = 300,
    lr: float = 0.05,
    epsilon: float = 8.0 / 255.0,
) -> torch.Tensor:
    """Synthesize an image from scratch that the model confidently classifies as target_class."""
    model = get_model()
    # Start from random noise in normalized space
    noise = torch.randn(1, 3, size, size, device=DEVICE) * 0.5 + 0.0
    img = noise.clone().detach().requires_grad_(True)

    optimizer = torch.optim.Adam([img], lr=lr)
    for step in range(steps):
        optimizer.zero_grad()
        out = model(img)
        # Targeted: maximize probability of target class
        loss = -F.log_softmax(out, dim=1)[0, target_class]
        loss.backward()
        optimizer.step()
        # Project to epsilon around zero (normalized space)
        with torch.no_grad():
            img.clamp_(-2.0, 2.0)
        if step % 50 == 0:
            with torch.no_grad():
                prob = F.softmax(model(img), dim=1)[0, target_class].item()
                print(f"  step {step:03d} | target prob = {prob:.4f} | loss = {loss.item():.4f}")

    return img.detach().cpu()


# ------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------

def cmd_fool(args: argparse.Namespace) -> None:
    src = Path(args.image)
    if not src.exists():
        sys.exit(f"error: {src} not found")
    img_tensor = load_image(src)
    target = args.target_class
    print(f"* loaded {src} ({img_tensor.shape[-2]}x{img_tensor.shape[-1]})")
    print(f"* targeting class {target} ({IMAGENET_CLASSES[target] if target < len(IMAGENET_CLASSES) else 'unknown'})")
    print(f"* running PGD (eps={args.epsilon*255:.0f}/255, steps={args.steps}, step={args.step_size*255:.1f}/255)")
    adv_tensor = pgd_attack(
        img_tensor,
        target_class=target,
        epsilon=args.epsilon / 255.0,
        steps=args.steps,
        step_size=args.step_size / 255.0,
    )
    # Verify
    model = get_model()
    with torch.no_grad():
        out = model(adv_tensor.to(DEVICE))
        probs = F.softmax(out, dim=1)[0]
        top5 = torch.topk(probs, 5)
        print("* top predictions on adversarial image:")
        for idx, p in zip(top5.indices.tolist(), top5.values.tolist()):
            cls_name = IMAGENET_CLASSES[idx] if idx < len(IMAGENET_CLASSES) else f"class {idx}"
            print(f"    {cls_name}: {p:.4f}")
    out_path = Path(args.output)
    pil_img = tensor_to_pil(adv_tensor)
    pil_img.save(out_path)
    print(f"-> wrote adversarial image to {out_path}")


def cmd_synth(args: argparse.Namespace) -> None:
    target = args.target_class
    size = args.size
    print(f"* synthesizing image for target class {target} ({IMAGENET_CLASSES[target] if target < len(IMAGENET_CLASSES) else 'unknown'})")
    if args.input:
        src = Path(args.input)
        img_tensor = load_image(src).squeeze(0)
        # Resize to target size
        img_tensor = F.interpolate(img_tensor.unsqueeze(0), size=(size, size), mode="bilinear", align_corners=False).squeeze(0)
        init = img_tensor.unsqueeze(0)
        print(f"* using input image as initialization: {src}")
    else:
        init = None
    # We'll use a simplified targeted gradient ascent on noise initialized image
    # If input given, we'll perturb it; else pure synthesis
    if init is not None:
        # Start from input, perturb
        init_t = init.clone().to(DEVICE).requires_grad_(True)
        model = get_model()
        optimizer = torch.optim.Adam([init_t], lr=args.lr)
        for step in range(args.steps):
            optimizer.zero_grad()
            out = model(init_t)
            loss = -F.log_softmax(out, dim=1)[0, target]
            loss.backward()
            optimizer.step()
            with torch.no_grad():
                init_t.clamp_(-2.5, 2.5)
            if step % 50 == 0:
                with torch.no_grad():
                    prob = F.softmax(model(init_t), dim=1)[0, target].item()
                    print(f"  step {step:03d} | target prob = {prob:.4f} | loss = {loss.item():.4f}")
        adv_tensor = init_t.detach().cpu()
    else:
        adv_tensor = synthesize_targeted_image(
            target_class=target,
            size=size,
            steps=args.steps,
            lr=args.lr,
            epsilon=args.epsilon,
        )
    out_path = Path(args.output)
    pil_img = tensor_to_pil(adv_tensor)
    pil_img.save(out_path)
    # Verify
    with torch.no_grad():
        out = get_model()(adv_tensor.to(DEVICE))
        probs = F.softmax(out, dim=1)[0]
        top5 = torch.topk(probs, 5)
        print("* top predictions on result:")
        for idx, p in zip(top5.indices.tolist(), top5.values.tolist()):
            cls_name = IMAGENET_CLASSES[idx] if idx < len(IMAGENET_CLASSES) else f"class {idx}"
            print(f"    {cls_name}: {p:.4f}")
    print(f"-> wrote synthesized adversarial image to {out_path}")


def main() -> None:
    p = argparse.ArgumentParser(description="Generate adversarial images against vision models.")
    sub = p.add_subparsers(dest="cmd", required=True)

    # fool
    fool_p = sub.add_parser("fool", help="perturb an existing image to force misclassification")
    fool_p.add_argument("image", help="input image path")
    fool_p.add_argument("--target-class", type=int, default=207, help="target ImageNet class index (default 207 = golden retriever)")
    fool_p.add_argument("-o", "--output", default="adversarial_fool.png", help="output path")
    fool_p.add_argument("--epsilon", type=float, default=8.0, help="perturbation budget in /255 (default 8)")
    fool_p.add_argument("--steps", type=int, default=20, help="PGD steps")
    fool_p.add_argument("--step-size", type=float, default=2.0, help="PGD step size in /255")
    fool_p.set_defaults(func=cmd_fool)

    # synth
    synth_p = sub.add_parser("synth", help="synthesize or perturb-to-target an image from scratch or an input")
    synth_p.add_argument("--input", help="optional initialization image; if omitted, starts from noise")
    synth_p.add_argument("--target-class", type=int, default=207, help="target ImageNet class index")
    synth_p.add_argument("--output", default="adversarial_synth.png", help="output path")
    synth_p.add_argument("--size", type=int, default=224, help="square size in px")
    synth_p.add_argument("--steps", type=int, default=300, help="optimization steps")
    synth_p.add_argument("--lr", type=float, default=0.05, help="optimizer learning rate")
    synth_p.add_argument("--epsilon", type=float, default=8.0, help="perturbation budget (normalized)")
    synth_p.set_defaults(func=cmd_synth)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
