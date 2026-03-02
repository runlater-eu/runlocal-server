defmodule Runlocal.Subdomain do
  @adjectives ~w(
    swift brave calm cool dark fast firm glad gold keen
    kind lean lite loud mild neat pale pure rare rich
    safe slim soft tall thin warm wild wise bold deep
    fair fine free full good high long nice open real
    true blue cold dear easy flat gray half hard huge
    just last lazy left live lost main mean next pink
    able aged airy avid bare bent best born busy clay
    cozy cute damp dawn deft dire done drab drip dual
    dull dusk each edge epic even fell fern fiery folk
    fond four foxy gale glow grim grit hale haze herb
    holy hush iced idle iron jade jazz lake lark late
    lava leaf less lime lord lush malt mars maze mesa
    mint misty moon moor moss muse navy neon noon nova
    opal onyx peak pine plum pond port prim quad reed
    reef rise rock root ruby sage sand silk snow song
    star surf teal tide tidy trim twig vast vine volt
    warp wave west whip zinc zeal zero zone
  )

  @animals ~w(
    tiger panda koala eagle shark whale robin crane heron otter
    falcon parrot lizard ferret badger beaver jackal coyote marten osprey
    toucan condor magpie hornet spider beetle mantis shrimp salmon turtle
    dragon monkey donkey alpaca jaguar cougar bobcat walrus hermit newt
    iguana python moose lemur viper cobra raven finch dove bison
    camel chimp corgi dingo egret gecko gibbon goose grouse guppy
    hyena ibis impala kiwi llama macaw mamba mink narwhal ocelot
    okapi orca oriole owl pelican perch pigeon piper plover pony
    quail rabbit rook sable seal snipe squid stork swift tern
    trout vixen weasel wombat wren yak zebra hound marlin oyster
    mule puma stoat tapir dhole fossa krait skink tokay axolotl
    bongo civet duiker eland frogmouth gannet harrier hoopoo jacana kakapo
    loris marmot numbat olingo pademelon quetzal roadrunner serval tarsier urial
    vervet wallaby xerus yapok zander anhinga bushbuck cheetah dugong ermine
    fennec gharial hamster indri junco korhaan langur manatee nilgai
  )

  def generate do
    subdomain = random_subdomain()

    case Runlocal.Registry.lookup(subdomain) do
      nil -> subdomain
      _ -> generate()
    end
  end

  defp random_subdomain do
    adj = Enum.random(@adjectives)
    animal = Enum.random(@animals)
    "#{adj}-#{animal}"
  end

  def pick_subdomain(org_slug, "pro", requested) when is_binary(requested) and requested != "" do
    if valid_subdomain?(requested), do: requested, else: org_slug
  end

  def pick_subdomain(org_slug, _tier, _requested), do: org_slug

  def valid_subdomain?(s) when is_binary(s) do
    Regex.match?(~r/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/, s)
  end

  def valid_subdomain?(_), do: false

  def adjectives, do: @adjectives
  def animals, do: @animals
end
