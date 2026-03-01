defmodule Runlocal.Subdomain do
  @adjectives ~w(
    swift brave calm cool dark fast firm glad gold keen
    kind lean lite loud mild neat pale pure rare rich
    safe slim soft tall thin warm wild wise bold deep
    fair fine free full good high long nice open real
    true blue cold dear easy flat gray half hard huge
    just last lazy left live lost main mean next pink
  )

  @animals ~w(
    tiger panda koala eagle shark whale robin crane heron otter
    falcon parrot lizard ferret badger beaver jackal coyote marten osprey
    toucan condor magpie hornet spider beetle mantis shrimp salmon turtle
    dragon monkey donkey alpaca jaguar cougar bobcat walrus hermit newt
    iguana python falcon moose lemur viper cobra raven finch dove
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

  def adjectives, do: @adjectives
  def animals, do: @animals
end
