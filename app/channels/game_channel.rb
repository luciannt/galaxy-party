class GameChannel < ApplicationCable::Channel
  def subscribed
    stop_all_streams
    stream_from "game_channel"
  end

  def unsubscribed
    puts "Unsubscribed"
    ActionCable.server.broadcast "game_channel", { type: "unsubscribe" }.to_json
    stop_all_streams()
  end

  def received(data)
    ActionCable.server.broadcast("game_channel", data)
  end

  def game_check(opts)
    ActionCable.server.broadcast("game_channel", { type: "CHECKING GAME", payload: opts })

    if (opts["user_id"])
      user = User.find(opts["user_id"])
    else
      ActionCable.server.broadcast("game_channel", { type: "FAILURE", message: "No user id supplied, please log in" })
    end

    if opts["code"]
      ActionCable.server.broadcast("game_channel", { type: "CHECK_GAME_VIABILITY", payload: Game.can_start_game(opts["code"]) })
    end

    if user && opts["code"]
      game = Game.find_by_game_code(opts["code"])
      gamePlayers = Player.where(game: game)

      playerArr = []
      gamePlayers.each do |player|
        user = User.find(player[:user_id])
        playerArr.append({ active_hand: player[:active_hand], hands_data: player[:hands_data], username: user[:username], id: user[:id], is_turn: game[:player_turn] == user[:id], end: game[:end], hand_score: player[:hand_score] })
      end

      ActionCable.server.broadcast("game_channel", { type: "CURRENT_PLAYERS", payload: playerArr })
      ActionCable.server.broadcast("game_channel", { type: "GAME_STARTED", payload: game[:started] })

      if !(gamePlayers.exists? user[:id])
        Game.join_game(opts["user_id"], opts["code"])
      end
    end
  end

  def start_game(opts)
    Game.start_game(opts["code"])

    game = Game.find_by_game_code(opts["code"])
    gamePlayers = Player.where(game: game)

    game.player_turn = gamePlayers[0][:user_id]
    game.save

    gamePlayers.each do |player|
      Game.deal(opts["code"], player)
      Game.hit(opts["code"], player_id: player[:id])
    end

    ActionCable.server.broadcast("game_channel", { type: "DEALT", payload: gamePlayers })
  end

  def new_game(opts)
    game = Game.new_game(SecureRandom.urlsafe_base64, opts["user_id"])
    ActionCable.server.broadcast("game_channel", { type: "GAME_CREATED", payload: game[:game_code] })
  end

  def hit(opts)
    game = Game.find_by_game_code(opts["code"])
    player = Player.where(game: game, user: opts["user_id"]).first

    game = Game.hit(opts["code"], player_id: player[:id])
    ActionCable.server.broadcast("game_channel", { type: "PLAYER_HIT", payload: game })
  end

  def stand(opts)
    game = Game.find_by_game_code(opts["code"])
    player = Player.where(game: game, user: opts["user_id"]).first

    game = Game.stand(opts["code"], player)
    ActionCable.server.broadcast("game_channel", { type: "PLAYER_HIT", payload: game })
  end

  private

  def find_user_id
    user = User.find(params[:id])
  end
end
