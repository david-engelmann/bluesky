open H2

module Http_client = struct
    module Client = H2_lwt_unix.Client
    let response_handler notify_response_received response response_body =
        match response.Response.status with
         | `OK ->
            let rec read_response () =
                Body.Reader.schedule_read
                  response_body
                  ~on_read:(fun bigstring ~off  ~len ->
                   let response_fragment = Bytes.create len in
                   Bigstringaf.blit_to_bytes
                    bigstring
                    ~src_off:off
                    response_fragment
                    ~dst_off:0
                    ~len;
                   print_string (Bytes.to_string response_fragment);
                   read_response ())
                  ~on_eof:(fun () ->
                    Lwt.wakeup_later notify_response_received ())
            in
            read_response ()
         | _ ->
            Format.eprintf "Unsuccessful response: %a\n%!" Response.pp_hum response;
            exit 1

    let error_handler _error =
        Format.eprintf "Unsuccessful request!\n%!";
        exit 1

    open Lwt.Infix

    let print_addr_info (addr_info : Unix.addr_info) : unit =
      match addr_info.Unix.ai_addr with
      | Unix.ADDR_INET (addr, port) ->
        Printf.printf "Address: %s, Port: %d\n" (Unix.string_of_inet_addr addr) port
      | _ ->
        Printf.printf "Unknown address format\n"

    let unpack_addr_info addr =
        match addr.Unix.ai_addr with
         | Unix.ADDR_UNIX _ -> None
         | ADDR_INET (addr, port) -> Some (addr, port)

    let print_converted_list (converted_list : Unix.addr_info list) : unit =
      List.iter print_addr_info converted_list

    let get_addr_info (host : string) (port : int) : Unix.addr_info list Lwt.t =
        Lwt_unix.getaddrinfo host (string_of_int port) [ Unix.(AI_FAMILY PF_INET) ]

    let create_socket =
      Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0

    let connect_socket socket (addr_info : Unix.addr_info) =
      Lwt_unix.connect socket addr_info.Unix.ai_addr

    let create_socket_for_addr_info addr_info =
        let socket = create_socket in
        let%bind () = connect_socket socket addr_info in
        Lwt.return socket

    let create_get_request (host : string) : Request.t =
      Request.create
        `GET
        "/"
        ~scheme:"https"
        ~headers:
          Headers.(add_list empty [ ":authority", host ])

    let handle_response (response_received : unit Lwt.t) : unit Lwt.t =
        response_received >>= fun () ->
        Lwt.return_unit


    let perform_request (connection : Client.TCP.connection) (request : Request.t) : Body.Writer.t Lwt.t =
        let request_body =
            Client.TCP.request
                connection
                request
                ~error_handler:handle_error
                ~response_handler:response_handler
            in
            Body.Writer.close request_body;
            Lwt.return request_body

    let start_client (host : string) (port : int) =
        Lwt_main.run
          (
          get_addr_info host port
          >>= fun addrs ->
          let lwt_list =
            List.map Lwt.return addrs
          in
          Lwt_list.iter_p (fun addr ->
            addr >>= fun addr_info ->
            let%bind socket = create_socket_for_addr_info addr_info in
            let request =
                Request.create
                `GET
                "/"
                ~scheme:"https"
                ~headers:
                    Headers.(add_list empty [ ":authority", host ])
            in
            let response_received, notify_response_received = Lwt.wait () in
            let response_handler = response_handler notify_response_received in
            Client.TLS.create_connection_with_default ~error_handler socket
            >>= fun connection ->
            let request_body =
              Client.TLS.request connection request ~error_handler ~response_handler
            in
            Body.Writer.close request_body;
            response_received) [List.hd lwt_list] 
          >>= fun _ -> Lwt.return_unit)

    (*
    let start_client (host : string) (port : int) =
        Lwt_main.run
          (
          get_addr_info host port
          >>= fun addresses ->
              let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
              Lwt_unix.connect socket (List.hd addresses).Unix.ai_addr >>= fun () ->
              let request =
                  Request.create
                   `GET
                   "/"
                   ~scheme:"https"
                   ~headers:
                       Headers.(add_list empty [ ":authority", host ])
              in
              let response_received, notify_response_received = Lwt.wait () in
              let response_handler = response_handler notify_response_received in
              Client.TLS.create_connection_with_default ~error_handler socket
              >>= fun connection ->

              let request_body =
                Client.TLS.request connection request ~error_handler ~response_handler
              in
              Body.Writer.close request_body;
              response_received )
     *)
end



